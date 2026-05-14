import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
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
  Either<AuthFailure, Unit> signInWithGoogleResult = const Right(unit);
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
  int signInWithGoogleCalls = 0;

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
  Future<Either<AuthFailure, Unit>> signInWithGoogle() async {
    signInWithGoogleCalls++;
    return signInWithGoogleResult;
  }

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

  // ----- MFA -----
  Either<AuthFailure, MfaTotpEnrollment> enrollTotpResult = const Right(
    MfaTotpEnrollment(
      factorId: 'fake-factor',
      secret: 'JBSWY3DPEHPK3PXP',
      qrCodeSvg: '<svg/>',
      uri: 'otpauth://totp/myapp:test@example.com?secret=JBSWY3DPEHPK3PXP',
    ),
  );
  Either<AuthFailure, Unit> verifyMfaEnrollmentResult = const Right(unit);
  Either<AuthFailure, Unit> challengeMfaResult = const Right(unit);
  Either<AuthFailure, List<MfaFactor>> listFactorsResult = const Right([]);
  Either<AuthFailure, Unit> unenrollMfaResult = const Right(unit);
  bool mfaChallengePending = false;

  String? lastEnrollTotpName;
  String? lastVerifyMfaFactorId;
  String? lastVerifyMfaCode;
  String? lastChallengeMfaFactorId;
  String? lastChallengeMfaCode;

  @override
  Future<Either<AuthFailure, MfaTotpEnrollment>> enrollTotp({
    String? friendlyName,
  }) async {
    lastEnrollTotpName = friendlyName;
    return enrollTotpResult;
  }

  @override
  Future<Either<AuthFailure, Unit>> verifyMfaEnrollment({
    required String factorId,
    required String code,
  }) async {
    lastVerifyMfaFactorId = factorId;
    lastVerifyMfaCode = code;
    return verifyMfaEnrollmentResult;
  }

  @override
  Future<Either<AuthFailure, Unit>> challengeAndVerifyMfa({
    required String factorId,
    required String code,
  }) async {
    lastChallengeMfaFactorId = factorId;
    lastChallengeMfaCode = code;
    return challengeMfaResult;
  }

  @override
  Future<Either<AuthFailure, List<MfaFactor>>> listMfaFactors() async =>
      listFactorsResult;

  @override
  Future<Either<AuthFailure, Unit>> unenrollMfa(String factorId) async =>
      unenrollMfaResult;

  @override
  bool isMfaChallengePending() => mfaChallengePending;
}
