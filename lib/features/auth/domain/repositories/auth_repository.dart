import 'package:fpdart/fpdart.dart';

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
}
