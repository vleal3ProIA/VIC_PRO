import 'package:fpdart/fpdart.dart';
import 'package:myapp/core/utils/app_logger.dart';
import 'package:myapp/features/auth/application/auth_redirect.dart';
import 'package:myapp/features/auth/data/datasources/auth_supabase_datasource.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:myapp/features/auth/domain/entities/sign_up_request.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';
import 'package:myapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({required AuthSupabaseDataSource dataSource})
      : _dataSource = dataSource;

  final AuthSupabaseDataSource _dataSource;

  @override
  Future<Either<AuthFailure, SignUpResult>> signUp(
    SignUpRequest request,
  ) async {
    try {
      final res = await _dataSource.signUp(
        email: request.email,
        password: request.password,
        username: request.username,
        redirectTo: AuthRedirect.resolve(AuthRedirectType.signup),
        locale: request.locale,
        themeMode: request.themeMode,
      );
      final needsConfirmation = res.session == null;
      return Right(
        SignUpResult(
          email: request.email,
          needsEmailConfirmation: needsConfirmation,
        ),
      );
    } on AuthException catch (e, st) {
      AppLogger.w('signUp AuthException: ${e.code} ${e.message}');
      return Left(_mapAuthException(e, st));
    } catch (e, st) {
      AppLogger.e('signUp unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> resendVerificationEmail(
    String email,
  ) async {
    try {
      await _dataSource.resendSignupConfirmation(
        email: email,
        redirectTo: AuthRedirect.resolve(AuthRedirectType.signup),
      );
      return const Right(unit);
    } on AuthException catch (e, st) {
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _dataSource.signInWithPassword(email: email, password: password);
      return const Right(unit);
    } on AuthException catch (e, st) {
      AppLogger.w('signIn AuthException: ${e.code} ${e.message}');
      return Left(_mapAuthException(e, st));
    } catch (e, st) {
      AppLogger.e('signIn unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> signOut() async {
    try {
      await _dataSource.signOut();
      return const Right(unit);
    } on AuthException catch (e, st) {
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> signInWithGoogle() async {
    try {
      await _dataSource.signInWithGoogle(
        redirectTo: AuthRedirect.resolve(AuthRedirectType.oauth),
      );
      return const Right(unit);
    } on AuthException catch (e, st) {
      AppLogger.w('signInWithGoogle AuthException: ${e.code} ${e.message}');
      return Left(_mapAuthException(e, st));
    } catch (e, st) {
      AppLogger.e('signInWithGoogle unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> signInWithApple() async {
    try {
      await _dataSource.signInWithApple(
        redirectTo: AuthRedirect.resolve(AuthRedirectType.oauth),
      );
      return const Right(unit);
    } on AuthException catch (e, st) {
      AppLogger.w('signInWithApple AuthException: ${e.code} ${e.message}');
      return Left(_mapAuthException(e, st));
    } catch (e, st) {
      AppLogger.e('signInWithApple unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> sendPasswordReset(String email) async {
    try {
      await _dataSource.sendPasswordReset(
        email: email,
        redirectTo: AuthRedirect.resolve(AuthRedirectType.recovery),
      );
      return const Right(unit);
    } on AuthException catch (e, st) {
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> updatePassword(String newPassword) async {
    try {
      await _dataSource.updatePassword(newPassword);
      return const Right(unit);
    } on AuthException catch (e, st) {
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _dataSource.currentEmail;
    if (email == null) {
      return const Left(AuthUnknown(message: 'No active session'));
    }
    try {
      // 1) Reautenticar: Supabase updateUser no valida la contraseña
      //    actual, así que lo hacemos nosotros con un signIn silencioso.
      await _dataSource.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException catch (e, st) {
      AppLogger.w('changePassword reauth failed: ${e.code}');
      // Contraseña actual incorrecta.
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
    try {
      // 2) Actualizar a la nueva.
      await _dataSource.updatePassword(newPassword);
      return const Right(unit);
    } on AuthException catch (e, st) {
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> deleteAccount({
    required String password,
  }) async {
    final email = _dataSource.currentEmail;
    if (email == null) {
      return const Left(AuthUnknown(message: 'No active session'));
    }
    // 1) Re-autenticacion via Edge Function `verify-password` (PR-F).
    //    Antes (pre PR-F) llamabamos a signInWithPassword en cliente, lo
    //    cual rotaba la sesion + no dejaba marker server-side. Ahora
    //    `verify-password` valida server-side, registra una "recent
    //    verification" con action_kind='delete_account' (TTL 5 min),
    //    y la Edge Function `delete-account` la consume antes de borrar
    //    al user. Esto cierra el agujero de "JWT robado que llama
    //    directo a delete-account saltandose el form de password".
    try {
      await _dataSource.verifyPasswordForAction(
        password: password,
        actionKind: 'delete_account',
      );
    } on AuthException catch (e, st) {
      AppLogger.w('deleteAccount reauth failed: ${e.message}');
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
    // 2) Invocar la Edge Function que borra el usuario de auth.users.
    //    `delete-account` chequea has_recent_verification('delete_account')
    //    en el servidor antes de actuar; si por algun bug no estuviera,
    //    devuelve 403 reauth_required.
    try {
      await _dataSource.deleteAccount();
    } on AuthException catch (e, st) {
      AppLogger.w('deleteAccount function failed: ${e.message}');
      return Left(_mapAuthException(e, st));
    } catch (e, st) {
      AppLogger.e('deleteAccount unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
    // 3) Cerrar sesión local. El JWT ya no sirve, pero limpiamos el estado.
    //    Un fallo aquí no es crítico: la cuenta ya no existe.
    try {
      await _dataSource.signOut();
    } catch (_) {}
    return const Right(unit);
  }

  @override
  Future<Either<AuthFailure, Unit>> changeEmail(String newEmail) async {
    try {
      await _dataSource.updateEmail(
        newEmail: newEmail,
        redirectTo: AuthRedirect.resolve(AuthRedirectType.emailChange),
      );
      return const Right(unit);
    } on AuthException catch (e, st) {
      AppLogger.w('changeEmail failed: ${e.code} ${e.message}');
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> signInWithMagicLink(String email) async {
    try {
      await _dataSource.sendMagicLink(
        email: email,
        redirectTo: AuthRedirect.resolve(AuthRedirectType.magiclink),
      );
      return const Right(unit);
    } on AuthException catch (e, st) {
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> requestEmailOtp(String email) async {
    try {
      await _dataSource.sendEmailOtp(
        email: email,
        // Si el usuario pulsa el link en lugar de meter el código, también
        // funciona — caemos en el callback como magic link.
        redirectTo: AuthRedirect.resolve(AuthRedirectType.magiclink),
      );
      return const Right(unit);
    } on AuthException catch (e, st) {
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    try {
      await _dataSource.verifyEmailOtp(email: email, token: token);
      return const Right(unit);
    } on AuthException catch (e, st) {
      AppLogger.w('verifyEmailOtp AuthException: ${e.code} ${e.message}');
      return Left(_mapOtpAuthException(e, st));
    } catch (e, st) {
      AppLogger.e('verifyEmailOtp unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  // ----- MFA TOTP ----------------------------------------------------------

  @override
  Future<Either<AuthFailure, MfaTotpEnrollment>> enrollTotp({
    String? friendlyName,
  }) async {
    try {
      final res = await _dataSource.enrollTotp(friendlyName: friendlyName);
      final totp = res.totp;
      if (totp == null) {
        return const Left(
          AuthUnknown(message: 'Supabase did not return a TOTP payload.'),
        );
      }
      return Right(
        MfaTotpEnrollment(
          factorId: res.id,
          secret: totp.secret,
          qrCodeSvg: totp.qrCode,
          uri: totp.uri,
        ),
      );
    } on AuthException catch (e, st) {
      AppLogger.w('enrollTotp ${e.code} ${e.message}');
      final failure = _mapAuthException(e, st);
      // Caso opaco ("Algo salió mal"): lo elevamos a error para que llegue a
      // Sentry y a la consola con el code REAL de GoTrue. Así diagnosticamos
      // causas como TOTP deshabilitado en el proyecto o límite de factores,
      // que de otro modo quedan ocultas tras el mensaje genérico.
      if (failure is AuthUnknown) {
        AppLogger.e(
          'enrollTotp failed code=${e.code}',
          error: e,
          stackTrace: st,
        );
      }
      return Left(failure);
    } catch (e, st) {
      AppLogger.e('enrollTotp unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> verifyMfaEnrollment({
    required String factorId,
    required String code,
  }) async {
    try {
      await _dataSource.challengeAndVerifyMfa(
        factorId: factorId,
        code: code,
      );
      return const Right(unit);
    } on AuthException catch (e, st) {
      AppLogger.w('verifyMfaEnrollment ${e.code} ${e.message}');
      return Left(_mapMfaAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> challengeAndVerifyMfa({
    required String factorId,
    required String code,
  }) async {
    try {
      await _dataSource.challengeAndVerifyMfa(
        factorId: factorId,
        code: code,
      );
      return const Right(unit);
    } on AuthException catch (e, st) {
      AppLogger.w('challengeAndVerifyMfa ${e.code} ${e.message}');
      return Left(_mapMfaAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, List<MfaFactor>>> listMfaFactors() async {
    try {
      final res = await _dataSource.listMfaFactors();
      final factors = [
        ...res.totp.map(
          (f) => MfaFactor(
            id: f.id,
            type: f.factorType.name,
            status: f.status.name,
            friendlyName: f.friendlyName,
          ),
        ),
      ];
      return Right(factors);
    } on AuthException catch (e, st) {
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> unenrollMfa(String factorId) async {
    try {
      await _dataSource.unenrollMfaFactor(factorId);
      return const Right(unit);
    } on AuthException catch (e, st) {
      return Left(_mapAuthException(e, st));
    } catch (e) {
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  bool isMfaChallengePending() {
    final aal = _dataSource.getAal();
    final current = aal.currentLevel;
    final next = aal.nextLevel;
    if (current == null || next == null) return false;
    return current != next;
  }

  @override
  Future<Either<AuthFailure, List<String>>> generateRecoveryCodes() async {
    try {
      final codes = await _dataSource.generateRecoveryCodes();
      return Right(codes);
    } on AuthException catch (e, st) {
      AppLogger.w('generateRecoveryCodes ${e.statusCode} ${e.message}');
      return Left(_mapAuthException(e, st));
    } catch (e, st) {
      AppLogger.e('generateRecoveryCodes unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> verifyRecoveryCode(String code) async {
    try {
      await _dataSource.verifyRecoveryCode(code);
      return const Right(unit);
    } on AuthException catch (e, st) {
      AppLogger.w('verifyRecoveryCode ${e.statusCode} ${e.message}');
      // 401 de la Edge Function = código inválido o ya usado.
      if (e.statusCode == '401') {
        return Left(AuthMfaInvalid(cause: e));
      }
      return Left(_mapAuthException(e, st));
    } catch (e, st) {
      AppLogger.e('verifyRecoveryCode unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  AuthFailure _mapMfaAuthException(AuthException e, StackTrace st) {
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    if (code == 'invalid_credentials' ||
        code == 'mfa_verification_failed' ||
        msg.contains('invalid') ||
        msg.contains('mfa') ||
        msg.contains('totp')) {
      return AuthMfaInvalid(cause: e);
    }
    return _mapAuthException(e, st);
  }

  /// El token OTP, cuando es incorrecto/expirado/ya usado, devuelve
  /// `otp_expired`, `invalid_otp`, `invalid_token` o simplemente
  /// `invalid_credentials`. Lo normalizamos a `AuthOtpInvalid` para que la
  /// UI muestre un mensaje específico de OTP (no "email o contraseña
  /// incorrectos" — que confunde al usuario).
  AuthFailure _mapOtpAuthException(AuthException e, StackTrace st) {
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    if (code == 'otp_expired' ||
        code == 'invalid_otp' ||
        code == 'invalid_token' ||
        code == 'invalid_credentials' ||
        msg.contains('token') ||
        msg.contains('otp')) {
      return AuthOtpInvalid(cause: e);
    }
    return _mapAuthException(e, st);
  }

  AuthFailure _mapAuthException(AuthException e, StackTrace st) {
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();

    // 429 desde nuestras Edge Functions = rate limit aplicado por nosotros.
    if (e.statusCode == '429') {
      return AuthRateLimited(cause: e);
    }

    if (code == 'user_already_exists' ||
        msg.contains('already registered') ||
        msg.contains('user already')) {
      return AuthUserAlreadyExists(cause: e);
    }
    if (code == 'weak_password') {
      return AuthWeakPassword(cause: e);
    }
    if (code == 'email_not_confirmed') {
      return AuthEmailNotConfirmed(cause: e);
    }
    if (code == 'over_request_rate_limit' || msg.contains('rate limit')) {
      return AuthRateLimited(cause: e);
    }
    if (code == 'invalid_credentials' ||
        msg.contains('invalid login credentials')) {
      return AuthInvalidCredentials(cause: e);
    }
    // Caso no mapeado: arrastramos el code de GoTrue dentro del message para
    // que el detalle técnico (visible en la pantalla de error) revele la
    // causa real (p. ej. `mfa_factor_name_conflict`, `over_enrolled_factors`,
    // o un TOTP enroll deshabilitado en el proyecto).
    final detail = code.isNotEmpty ? '[$code] ${e.message}' : e.message;
    return AuthUnknown(cause: e, message: detail);
  }
}
