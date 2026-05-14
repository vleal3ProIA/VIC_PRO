class SignUpRequest {
  const SignUpRequest({
    required this.username,
    required this.email,
    required this.password,
    this.locale = 'en',
    this.themeMode = 'system',
  });

  final String username;
  final String email;
  final String password;

  /// Idioma que el usuario está usando al registrarse (`es`, `en`, …). Viaja
  /// en el metadata del signUp para que el trigger cree el perfil con el
  /// idioma correcto en vez del default 'en'.
  final String locale;

  /// Tema activo al registrarse (`system`, `light`, `dark`).
  final String themeMode;
}

/// Resultado de un signUp exitoso.
class SignUpResult {
  const SignUpResult({required this.email, required this.needsEmailConfirmation});

  final String email;
  final bool needsEmailConfirmation;
}
