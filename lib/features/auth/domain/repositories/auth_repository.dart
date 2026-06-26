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
  ///
  /// [captchaToken]: token de Cloudflare Turnstile cuando Bot protection
  /// está activado en Supabase Auth. Sin él, el endpoint `/token` devuelve
  /// `captcha_failed`.
  Future<Either<AuthFailure, Unit>> signIn({
    required String email,
    required String password,
    String? captchaToken,
  });

  /// Cierra sesión.
  Future<Either<AuthFailure, Unit>> signOut();

  /// Inicia el login con Google (OAuth). En web dispara un redirect de página
  /// completa; la sesión llega después por el callback `type=oauth`.
  /// Devuelve `Right(unit)` si el redirect se lanzó correctamente.
  Future<Either<AuthFailure, Unit>> signInWithGoogle();

  /// Inicia el login con Apple (OAuth). Mismo comportamiento que
  /// [signInWithGoogle]: redirect de página completa en web.
  Future<Either<AuthFailure, Unit>> signInWithApple();

  /// Envía el email de recuperación de contraseña.
  ///
  /// [captchaToken]: token de Cloudflare Turnstile. El endpoint `/recover`
  /// también requiere captcha si Bot protection está activado.
  Future<Either<AuthFailure, Unit>> sendPasswordReset(
    String email, {
    String? captchaToken,
  });

  /// Cambia la contraseña del usuario actual. Requiere sesión activa
  /// (se obtiene del callback de recovery o del panel privado).
  Future<Either<AuthFailure, Unit>> updatePassword(String newPassword);

  /// Envía un Magic Link al email indicado. El link abre sesión vía PKCE
  /// callback y redirige al usuario a `/home`.
  ///
  /// [captchaToken]: token de Cloudflare Turnstile. `/otp` (que cubre magic
  /// link + OTP) está protegido por Bot protection en Supabase Auth.
  Future<Either<AuthFailure, Unit>> signInWithMagicLink(
    String email, {
    String? captchaToken,
  });

  /// Envía un código OTP de 6 dígitos al email indicado.
  ///
  /// [captchaToken]: token de Cloudflare Turnstile. Mismo endpoint que el
  /// magic link (`/otp`) — exige captcha si Bot protection está activado.
  Future<Either<AuthFailure, Unit>> requestEmailOtp(
    String email, {
    String? captchaToken,
  });

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

  /// Genera (y reemplaza) los códigos de recuperación de MFA. Requiere que el
  /// usuario esté a AAL2. Devuelve los códigos en claro — solo se ven una vez.
  Future<Either<AuthFailure, List<String>>> generateRecoveryCodes();

  /// Verifica un código de recuperación durante el desafío MFA. Si es válido,
  /// elimina los factores MFA del usuario (recupera el acceso) y refresca la
  /// sesión. El usuario debería volver a configurar MFA después.
  Future<Either<AuthFailure, Unit>> verifyRecoveryCode(String code);

  // ----- Cambios desde el panel privado ------------------------------------

  /// Cambia la contraseña del usuario autenticado. Primero reautentica con
  /// la contraseña actual (Supabase `updateUser` no la valida por sí solo)
  /// y, si es correcta, aplica la nueva.
  Future<Either<AuthFailure, Unit>> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Inicia el cambio de email. Supabase envía email(s) de confirmación;
  /// el cambio se aplica al confirmar.
  Future<Either<AuthFailure, Unit>> changeEmail(String newEmail);

  /// Borra permanentemente la cuenta del usuario autenticado (derecho de
  /// supresión del GDPR). Reautentica con [password] para confirmar la
  /// identidad, invoca la Edge Function que elimina el usuario y cierra
  /// sesión. La acción es irreversible.
  Future<Either<AuthFailure, Unit>> deleteAccount({
    required String password,
  });
}
