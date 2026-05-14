import 'package:supabase_flutter/supabase_flutter.dart';

/// DataSource fino sobre el SDK de Supabase para auth.
/// El mapeo a `AuthFailure` se hace en el repositorio.
class AuthSupabaseDataSource {
  const AuthSupabaseDataSource(this._client);

  final SupabaseClient _client;

  /// Registro de usuario nuevo.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    required String redirectTo,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: redirectTo,
      data: {
        // Llega al trigger handle_new_user → tabla profiles.
        'username': username,
        'display_name': username,
      },
    );
  }

  /// Login email + password.
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Cierra la sesión activa.
  Future<void> signOut() => _client.auth.signOut();

  /// Inicia el login con Google (OAuth 2.0).
  ///
  /// En web hace un *full-page redirect* al consentimiento de Google y, tras
  /// aceptar, Supabase devuelve al navegador a `redirectTo` con la sesión en
  /// el fragmento (flujo implicit). Por eso el método no devuelve sesión: el
  /// resultado llega de forma asíncrona por `onAuthStateChange`.
  Future<bool> signInWithGoogle({required String redirectTo}) {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      authScreenLaunchMode: LaunchMode.platformDefault,
    );
  }

  /// Reenvía el email de verificación de signup.
  Future<ResendResponse> resendSignupConfirmation({
    required String email,
    required String redirectTo,
  }) {
    return _client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: redirectTo,
    );
  }

  /// Envía el email de recuperación de contraseña.
  Future<void> sendPasswordReset({
    required String email,
    required String redirectTo,
  }) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: redirectTo,
    );
  }

  /// Actualiza la contraseña del usuario actualmente autenticado.
  /// Se llama desde la pantalla `set_new_password` tras intercambiar el
  /// `code` del link de recovery por una sesión activa.
  Future<UserResponse> updatePassword(String newPassword) {
    return _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Envía un magic link (passwordless email).
  ///
  /// Si `shouldCreateUser` es `true`, se crea el usuario al firmar por
  /// primera vez. Lo dejamos en `true` por defecto para que el magic link
  /// sirva tanto para login como para signup sin contraseña.
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
    bool shouldCreateUser = true,
  }) {
    return _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: redirectTo,
      shouldCreateUser: shouldCreateUser,
    );
  }

  /// Envía un código OTP de 6 dígitos al email indicado.
  ///
  /// Backend: comparte método con magic link (`signInWithOtp`). La plantilla
  /// de email muestra tanto el link como el código; el usuario usa el que
  /// prefiera. En la app, el flujo OTP redirige a la pantalla de verificar
  /// código y el del magic link al callback.
  Future<void> sendEmailOtp({
    required String email,
    required String redirectTo,
    bool shouldCreateUser = true,
  }) {
    return _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: redirectTo,
      shouldCreateUser: shouldCreateUser,
    );
  }

  /// Verifica un código OTP de 6 dígitos. Devuelve la sesión activa si es
  /// válido.
  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      type: OtpType.email,
      email: email,
      token: token,
    );
  }

  // ----- MFA TOTP ------------------------------------------------------------

  /// Inicia enrollment de un factor TOTP (Google Authenticator/Authy/etc.).
  /// Devuelve el secret, QR y factorId. NO completa el enrollment — el
  /// usuario debe verificar con un challenge después.
  Future<AuthMFAEnrollResponse> enrollTotp({String? friendlyName}) {
    return _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      friendlyName: friendlyName,
    );
  }

  /// Lanza un challenge sobre un factor (genera un challengeId interno
  /// que el usuario tiene que satisfacer con su código TOTP).
  Future<AuthMFAChallengeResponse> challengeMfaFactor(String factorId) {
    return _client.auth.mfa.challenge(factorId: factorId);
  }

  /// Verifica el código de 6 dígitos contra el challenge.
  Future<AuthMFAVerifyResponse> verifyMfaFactor({
    required String factorId,
    required String challengeId,
    required String code,
  }) {
    return _client.auth.mfa.verify(
      factorId: factorId,
      challengeId: challengeId,
      code: code,
    );
  }

  /// Atajo: challenge + verify en una sola llamada. Lo usa el login flow
  /// para que el usuario solo introduzca el código y nosotros gestionemos
  /// el challengeId internamente.
  Future<AuthMFAVerifyResponse> challengeAndVerifyMfa({
    required String factorId,
    required String code,
  }) {
    return _client.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code,
    );
  }

  /// Desenrola un factor (delete del lado de Supabase).
  Future<AuthMFAUnenrollResponse> unenrollMfaFactor(String factorId) {
    return _client.auth.mfa.unenroll(factorId);
  }

  /// Lista de factores enrollados (verificados o no).
  Future<AuthMFAListFactorsResponse> listMfaFactors() {
    return _client.auth.mfa.listFactors();
  }

  /// AAL actual y nivel siguiente requerido. Si `current < next`, el
  /// usuario tiene MFA pendiente de verificar.
  AuthMFAGetAuthenticatorAssuranceLevelResponse getAal() {
    return _client.auth.mfa.getAuthenticatorAssuranceLevel();
  }
}
