import 'package:fpdart/fpdart.dart';
import 'package:myapp/core/utils/app_logger.dart';
import 'package:myapp/features/auth/data/datasources/webauthn_supabase_datasource.dart';
import 'package:myapp/features/auth/data/webauthn/webauthn_js.dart' as js;
import 'package:myapp/features/auth/domain/entities/passkey_credential.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';
import 'package:myapp/features/auth/domain/repositories/webauthn_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Implementación del flujo WebAuthn. Coordina las dos vueltas al servidor
/// (options → verify) con la ceremonia del navegador en medio.
class WebauthnRepositoryImpl implements WebauthnRepository {
  const WebauthnRepositoryImpl({
    required WebauthnSupabaseDataSource dataSource,
  }) : _dataSource = dataSource;

  final WebauthnSupabaseDataSource _dataSource;

  @override
  Future<Either<AuthFailure, Unit>> registerPasskey({
    String? friendlyName,
  }) async {
    try {
      // 1) Pedimos options al servidor.
      final r = await _dataSource.getRegistrationOptions();
      final options = Map<String, dynamic>.from(r['options'] as Map);
      final challengeId = r['challengeId'] as String;

      // 2) El navegador hace la ceremonia (biometría / Windows Hello / …).
      final response = await js.startRegistration(options);

      // 3) Enviamos la respuesta al servidor para que la verifique y la
      //    guarde.
      await _dataSource.verifyRegistration(
        challengeId: challengeId,
        response: response,
        friendlyName: friendlyName,
      );
      return const Right(unit);
    } on AuthException catch (e) {
      AppLogger.w('registerPasskey AuthException: ${e.message}');
      return Left(_mapPasskeyException(e));
    } catch (e, st) {
      AppLogger.e('registerPasskey unknown', error: e, stackTrace: st);
      return Left(AuthPasskeyFailed(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> loginWithPasskey() async {
    try {
      // 1) Options para autenticación (discoverable, sin user previo).
      final r = await _dataSource.getAuthenticationOptions();
      final options = Map<String, dynamic>.from(r['options'] as Map);
      final challengeId = r['challengeId'] as String;

      // 2) Ceremonia en el navegador → el SO muestra el selector de passkey.
      final response = await js.startAuthentication(options);

      // 3) Verifica + obtiene token para mintar la sesión.
      final result = await _dataSource.verifyAuthentication(
        challengeId: challengeId,
        response: response,
      );

      // 4) Canjea el token → sesión Supabase real.
      await _dataSource.verifyMagicLinkToken(result.tokenHash);
      return const Right(unit);
    } on AuthException catch (e) {
      AppLogger.w('loginWithPasskey AuthException: ${e.message}');
      return Left(_mapPasskeyException(e));
    } catch (e, st) {
      AppLogger.e('loginWithPasskey unknown', error: e, stackTrace: st);
      return Left(AuthPasskeyFailed(cause: e, message: e.toString()));
    }
  }

  /// Mapea una `AuthException` del flujo de passkey: 429 → rate limited
  /// (mensaje específico al usuario), todo lo demás → fallo genérico de
  /// passkey.
  AuthFailure _mapPasskeyException(AuthException e) {
    if (e.statusCode == '429') {
      return AuthRateLimited(cause: e);
    }
    return AuthPasskeyFailed(cause: e, message: e.message);
  }

  @override
  Future<Either<AuthFailure, List<PasskeyCredential>>> listPasskeys() async {
    try {
      final rows = await _dataSource.listMyPasskeys();
      return Right(
        rows.map(PasskeyCredential.fromMap).toList(growable: false),
      );
    } on AuthException catch (e) {
      return Left(AuthUnknown(cause: e, message: e.message));
    } catch (e, st) {
      AppLogger.e('listPasskeys unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> deletePasskey(String id) async {
    try {
      await _dataSource.deletePasskey(id);
      return const Right(unit);
    } on AuthException catch (e) {
      return Left(AuthUnknown(cause: e, message: e.message));
    } catch (e, st) {
      AppLogger.e('deletePasskey unknown', error: e, stackTrace: st);
      return Left(AuthUnknown(cause: e, message: e.toString()));
    }
  }
}
