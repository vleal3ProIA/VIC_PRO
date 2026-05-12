import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/domain/entities/sign_up_request.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';
import 'package:myapp/features/auth/domain/repositories/auth_repository.dart';

/// Fake controlable de `AuthRepository` para tests de notifiers.
/// Cada método guarda los argumentos recibidos y devuelve la respuesta
/// que le inyectemos.
class FakeAuthRepository implements AuthRepository {
  Either<AuthFailure, SignUpResult> signUpResult =
      const Right(SignUpResult(email: '', needsEmailConfirmation: true));
  Either<AuthFailure, Unit> signInResult = const Right(unit);
  Either<AuthFailure, Unit> sendPasswordResetResult = const Right(unit);
  Either<AuthFailure, Unit> updatePasswordResult = const Right(unit);
  Either<AuthFailure, Unit> resendResult = const Right(unit);
  Either<AuthFailure, Unit> signOutResult = const Right(unit);
  Either<AuthFailure, Unit> magicLinkResult = const Right(unit);
  Either<AuthFailure, Unit> requestOtpResult = const Right(unit);
  Either<AuthFailure, Unit> verifyOtpResult = const Right(unit);

  String? lastSignInEmail;
  String? lastSignInPassword;
  String? lastResetEmail;
  String? lastUpdatedPassword;
  String? lastMagicLinkEmail;
  String? lastOtpRequestEmail;
  String? lastOtpVerifyEmail;
  String? lastOtpVerifyToken;

  @override
  Future<Either<AuthFailure, SignUpResult>> signUp(SignUpRequest request) async {
    return signUpResult;
  }

  @override
  Future<Either<AuthFailure, Unit>> resendVerificationEmail(String email) async {
    return resendResult;
  }

  @override
  Future<Either<AuthFailure, Unit>> signIn({
    required String email,
    required String password,
  }) async {
    lastSignInEmail = email;
    lastSignInPassword = password;
    return signInResult;
  }

  @override
  Future<Either<AuthFailure, Unit>> signOut() async => signOutResult;

  @override
  Future<Either<AuthFailure, Unit>> sendPasswordReset(String email) async {
    lastResetEmail = email;
    return sendPasswordResetResult;
  }

  @override
  Future<Either<AuthFailure, Unit>> updatePassword(String newPassword) async {
    lastUpdatedPassword = newPassword;
    return updatePasswordResult;
  }

  @override
  Future<Either<AuthFailure, Unit>> signInWithMagicLink(String email) async {
    lastMagicLinkEmail = email;
    return magicLinkResult;
  }

  @override
  Future<Either<AuthFailure, Unit>> requestEmailOtp(String email) async {
    lastOtpRequestEmail = email;
    return requestOtpResult;
  }

  @override
  Future<Either<AuthFailure, Unit>> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    lastOtpVerifyEmail = email;
    lastOtpVerifyToken = token;
    return verifyOtpResult;
  }
}
