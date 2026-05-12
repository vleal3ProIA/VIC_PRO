import 'package:fpdart/fpdart.dart';
import 'package:myapp/core/utils/app_logger.dart';
import 'package:myapp/features/auth/application/auth_redirect.dart';
import 'package:myapp/features/auth/data/datasources/auth_supabase_datasource.dart';
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

  AuthFailure _mapAuthException(AuthException e, StackTrace st) {
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();

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
    return AuthUnknown(cause: e, message: e.message);
  }
}
