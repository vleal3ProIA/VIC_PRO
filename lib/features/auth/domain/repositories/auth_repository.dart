import 'package:fpdart/fpdart.dart';

import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:myapp/features/auth/domain/entities/sign_up_request.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

abstract class AuthRepository {
  /// Registra un nuevo usuario. Si Supabase requiere confirmación por email
  /// (lo que activamos en dashboard), `needsEmailConfirmation` será `true`.
  Future<Either<AuthFailure, SignUpResult>> signUp(SignUpRequest request);

  /// Reenvía el email de verificación.
  Future<Either<AuthFailure, Unit>> resendVerificationEmail(String email);

  /// Login con email + password.
  Future<Either<AuthFailure, Unit>> signIn({
    required String email,
    required String password,
  });

  /// Cierra sesión.
  Future<Either<AuthFailure, Unit>> signOut();

  /// Envía el email de recuperación de contraseña.
  Future<Either<AuthFailure, Unit>> sendPasswordReset(String email);

  /// Cambia la contraseña del usuario actual. Requiere sesión activa
  /// (se obtiene del callback de recovery o del panel privado).
  Future<Either<AuthFailure, Unit>> updatePassword(String newPassword);

  /// Envía un Magic Link al email indicado. El link abre sesión vía PKCE
  /// callback y redirige al usuario a `/home`.
  Future<Either<AuthFailure, Unit>> signInWithMagicLink(String email);

  /// Envía un código OTP de 6 dígitos al email indicado.
  Future<Either<AuthFailure, Unit>> requestEmailOtp(String email);

  /// Verifica el código OTP. Si es válido abre sesión activa.
  Future<Either<AuthFailure, Unit>> verifyEmailOtp({
    required String email,
    required String token,
  });

  // ----- MFA TOTP ----------------------------------------------------------

  /// Inicia enrollment de un factor TOTP. Devuelve secret + QR.
  /// El usuario tiene que verificar con un código para completar.
  Future<Either<AuthFailure, MfaTotpEnrollment>> enrollTotp({
    String? friendlyName,
  });

  /// Verifica el código TOTP durante el enrollment (primer uso del factor).
  Future<Either<AuthFailure, Unit>> verifyMfaEnrollment({
    required String factorId,
    required String code,
  });

  /// Verifica el código TOTP durante el login (challenge para AAL2).
  /// Internamente lanza un challenge y verifica con el código.
  Future<Either<AuthFailure, Unit>> challengeAndVerifyMfa({
    required String factorId,
    required String code,
  });

  /// Lista los factores enrollados (verificados o no).
  Future<Either<AuthFailure, List<MfaFactor>>> listMfaFactors();

  /// Desenrola un factor (lo elimina de la cuenta).
  Future<Either<AuthFailure, Unit>> unenrollMfa(String factorId);

  /// `true` si el usuario actual tiene MFA pendiente de verificar
  /// (currentLevel = aal1, nextLevel = aal2).
  bool isMfaChallengePending();
}
