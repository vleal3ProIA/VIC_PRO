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

class ProfileUnknown extends ProfileFailure {
  const ProfileUnknown({super.cause, this.message});
  final String? message;
}
