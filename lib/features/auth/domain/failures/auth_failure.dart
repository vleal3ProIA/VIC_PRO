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

/// La contraseña elegida aparece en brechas de datos conocidas
/// (HaveIBeenPwned). Distinta de `AuthWeakPassword` (formato/longitud):
/// aquí el formato es válido pero la contraseña está comprometida y es
/// trivial de adivinar en credential stuffing / ataques de diccionario.
class AuthLeakedPassword extends AuthFailure {
  const AuthLeakedPassword({super.cause});
}

class AuthEmailNotConfirmed extends AuthFailure {
  const AuthEmailNotConfirmed({super.cause});
}

/// El email introducido no pertenece a ninguna cuenta. Se usa en los flujos
/// passwordless (magic link, código OTP), donde NO permitimos signup al vuelo
/// (`shouldCreateUser: false`): si el email es desconocido, mostramos un
/// mensaje claro que invita a registrarse en vez de crear cuenta de tapadillo.
class AuthEmailNotRegistered extends AuthFailure {
  const AuthEmailNotRegistered({super.cause});
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

/// El código de MFA (TOTP de la app autenticadora) es incorrecto. Distinto
/// del OTP por email: aquí la app del usuario es la fuente del código.
class AuthMfaInvalid extends AuthFailure {
  const AuthMfaInvalid({super.cause});
}

/// Cualquier fallo del flujo de passkeys (cancelado por el usuario, navegador
/// sin soporte, firma inválida, etc.). El detalle interno queda en `cause` /
/// `message`; la UI muestra un mensaje genérico.
class AuthPasskeyFailed extends AuthFailure {
  const AuthPasskeyFailed({super.cause, this.message});
  final String? message;
}

class AuthUnknown extends AuthFailure {
  const AuthUnknown({super.cause, this.message});
  final String? message;
}
