/// Errores de la capa de perfil. La presentación los mapea a strings i18n.
sealed class ProfileFailure {
  const ProfileFailure({this.cause});
  final Object? cause;
}

/// No hay sesión activa o el perfil no existe todavía.
class ProfileNotFound extends ProfileFailure {
  const ProfileNotFound({super.cause});
}

/// El username ya está en uso por otro usuario (violación de unique).
class ProfileUsernameTaken extends ProfileFailure {
  const ProfileUsernameTaken({super.cause});
}

class ProfileNetworkError extends ProfileFailure {
  const ProfileNetworkError({super.cause});
}

/// La imagen de avatar no paso la validacion de magic bytes. Sucede
/// si el usuario intenta subir un archivo cuyo contenido real no
/// coincide con su extension / Content-Type (ej. un .exe renombrado a
/// .png). Defensa contra MIME spoofing -- ver
/// `lib/core/security/image_magic_bytes.dart`.
class ProfileInvalidImage extends ProfileFailure {
  const ProfileInvalidImage({super.cause});
}

class ProfileUnknown extends ProfileFailure {
  const ProfileUnknown({super.cause, this.message});
  final String? message;
}
