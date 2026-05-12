import 'package:fpdart/fpdart.dart';

import 'package:myapp/features/auth/domain/entities/sign_up_request.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

abstract class AuthRepository {
  /// Registra un nuevo usuario. Si Supabase requiere confirmación por email
  /// (lo que activaremos en dashboard), `needsEmailConfirmation` será `true`.
  Future<Either<AuthFailure, SignUpResult>> signUp(SignUpRequest request);

  /// Reenvía el email de verificación.
  Future<Either<AuthFailure, Unit>> resendVerificationEmail(String email);
}
