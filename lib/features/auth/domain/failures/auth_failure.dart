/// Failures de auth que el repositorio devuelve hacia la capa de aplicación.
/// La presentación las mapea a strings localizados.
sealed class AuthFailure {
  const AuthFailure({this.cause});
  final Object? cause;
}

class AuthInvalidCredentials extends AuthFailure {
  const AuthInvalidCredentials({super.cause});
}

class AuthUserAlreadyExists extends AuthFailure {
  const AuthUserAlreadyExists({super.cause});
}

class AuthWeakPassword extends AuthFailure {
  const AuthWeakPassword({super.cause});
}

class AuthEmailNotConfirmed extends AuthFailure {
  const AuthEmailNotConfirmed({super.cause});
}

class AuthRateLimited extends AuthFailure {
  const AuthRateLimited({super.cause});
}

class AuthNetworkError extends AuthFailure {
  const AuthNetworkError({super.cause});
}

/// El código OTP introducido es incorrecto, expirado o ya usado.
/// Se diferencia de `AuthInvalidCredentials` porque éste se refiere a
/// email+password, no a OTP — el mensaje al usuario es distinto.
class AuthOtpInvalid extends AuthFailure {
  const AuthOtpInvalid({super.cause});
}

class AuthUnknown extends AuthFailure {
  const AuthUnknown({super.cause, this.message});
  final String? message;
}
