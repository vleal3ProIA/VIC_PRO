import 'package:fpdart/fpdart.dart';

import 'package:myapp/features/auth/domain/entities/passkey_credential.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

/// Repositorio de passkeys (WebAuthn).
abstract class WebauthnRepository {
  /// Registra un passkey nuevo para el usuario autenticado actual.
  /// El navegador disparará la ceremonia (biometría / Windows Hello /
  /// Touch ID).
  Future<Either<AuthFailure, Unit>> registerPasskey({
    String? friendlyName,
  });

  /// Inicia sesión con un passkey. El usuario NO necesita estar autenticado
  /// antes; tras verificar la firma, la app obtiene una sesión Supabase
  /// real (vía magic link interno).
  Future<Either<AuthFailure, Unit>> loginWithPasskey();

  /// Lista los passkeys registrados por el usuario actual.
  Future<Either<AuthFailure, List<PasskeyCredential>>> listPasskeys();

  /// Borra un passkey por id (UUID de fila, no credential_id).
  Future<Either<AuthFailure, Unit>> deletePasskey(String id);
}
