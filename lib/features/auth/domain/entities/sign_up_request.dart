class SignUpRequest {
  const SignUpRequest({
    required this.username,
    required this.email,
    required this.password,
    this.locale = 'en',
    this.themeMode = 'system',
    this.captchaToken,
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

  /// Token de captcha (Cloudflare Turnstile) que el cliente obtuvo al
  /// pasar el reto en el formulario. Supabase Auth lo valida server-side
  /// contra Cloudflare con la Secret Key configurada en el dashboard. Si
  /// es `null`, el signUp procede sin captcha (entornos de test o si
  /// `TURNSTILE_SITEKEY` está vacío).
  final String? captchaToken;
}

/// Resultado de un signUp exitoso.
class SignUpResult {
  const SignUpResult({required this.email, required this.needsEmailConfirmation});

  final String email;
  final bool needsEmailConfirmation;
}
