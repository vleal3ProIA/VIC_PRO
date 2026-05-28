import 'package:myapp/core/config/env_config.dart';
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
    required String locale,
    required String themeMode,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: redirectTo,
      data: {
        // Llega al trigger handle_new_user → tabla profiles.
        'username': username,
        'display_name': username,
        // Idioma y tema activos al registrarse: así el perfil se crea con
        // las preferencias correctas y no fuerza 'en' al primer login.
        'locale': locale,
        'theme_mode': themeMode,
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

  /// Inicia el login con Apple (Sign in with Apple).
  ///
  /// Igual que Google: en web hace un *full-page redirect* al consentimiento
  /// de Apple y la sesión llega de forma asíncrona por `onAuthStateChange`.
  Future<bool> signInWithApple({required String redirectTo}) {
    return _client.auth.signInWithOAuth(
      OAuthProvider.apple,
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

  /// Cambia el email del usuario actual. Supabase envía emails de
  /// confirmación (uno o dos según "Secure email change" en el dashboard).
  /// El cambio NO es inmediato: se aplica al confirmar.
  Future<UserResponse> updateEmail({
    required String newEmail,
    required String redirectTo,
  }) {
    return _client.auth.updateUser(
      UserAttributes(email: newEmail),
      emailRedirectTo: redirectTo,
    );
  }

  /// Email del usuario autenticado actual (para reautenticación).
  String? get currentEmail => _client.auth.currentUser?.email;

  /// Borra la cuenta del usuario autenticado invocando la Edge Function
  /// `delete-account` (que usa la `service_role` key del lado servidor).
  ///
  /// El SDK adjunta automáticamente el JWT del usuario, así que la función
  /// sabe a quién borrar. Lanza si la respuesta no es 200.
  Future<void> deleteAccount() async {
    final res = await _client.functions.invoke('delete-account');
    if (res.status != 200) {
      throw AuthException(
        'delete-account returned ${res.status}',
        statusCode: '${res.status}',
      );
    }
  }

  /// Verifica el [password] del user actual via Edge Function
  /// `verify-password` y registra una "recent verification" para el
  /// [actionKind] dado (TTL 5 min server-side). PR-F: las Edge Functions
  /// destructivas (delete-account, create-pat con scope write)
  /// consultan esa marca antes de actuar.
  ///
  /// Lanza `AuthException` con `statusCode='401'` y `message='invalid_password'`
  /// si el password es incorrecto, `'429'` si rate-limited.
  Future<void> verifyPasswordForAction({
    required String password,
    required String actionKind,
  }) async {
    final res = await _client.functions.invoke(
      'verify-password',
      body: {'password': password, 'action_kind': actionKind},
    );
    final data = res.data;
    if (res.status == 200 && data is Map && data['ok'] == true) {
      return;
    }
    // Extraer codigo del body si esta estructurado. Traducimos
    // 'invalid_password' (lo que devuelve verify-password) a
    // 'invalid_credentials' (el codigo estandar que _mapAuthException
    // reconoce y mapea a AuthInvalidCredentials).
    String code = 'unknown';
    if (data is Map) {
      final m = data.cast<String, dynamic>();
      final c = m['error'] as String?;
      if (c != null) {
        code = c == 'invalid_password' ? 'invalid_credentials' : c;
      }
    }
    throw AuthException(code, statusCode: '${res.status}');
  }

  /// Envía un magic link (passwordless email).
  ///
  /// `shouldCreateUser` POR DEFECTO `false`: los métodos passwordless son
  /// SOLO para usuarios ya registrados. Si el email no existe, Supabase
  /// responde con `otp_disabled` ("Signups not allowed for otp"); el
  /// repositorio lo mapea a `AuthEmailNotRegistered` y la UI muestra un
  /// mensaje que invita a registrarse — en vez de crear cuenta de tapadillo
  /// y enviar un email de confirmación que confunde al usuario.
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
    bool shouldCreateUser = false,
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
  ///
  /// `shouldCreateUser` POR DEFECTO `false`: por la misma razón que en el
  /// magic link, el código de acceso no puede crear cuentas al vuelo.
  Future<void> sendEmailOtp({
    required String email,
    required String redirectTo,
    bool shouldCreateUser = false,
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
    // `issuer` es OBLIGATORIO para TOTP en gotrue >=2.20: si no se pasa, el
    // SDK lanza ArgumentError ("expected an issuer for totp factor type") y el
    // enroll nunca llega al servidor. Es además la etiqueta del emisor que
    // muestra la app autenticadora (Google Authenticator/Authy/etc.).
    return _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: EnvConfig.appName,
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

  // ----- Códigos de recuperación de MFA --------------------------------------

  /// Genera (y reemplaza) los códigos de recuperación. Invoca la Edge
  /// Function `mfa-recovery`, que exige AAL2. Devuelve los códigos en claro.
  Future<List<String>> generateRecoveryCodes() async {
    final res = await _client.functions.invoke(
      'mfa-recovery',
      body: {'action': 'generate'},
    );
    if (res.status != 200) {
      throw AuthException(
        'mfa-recovery generate returned ${res.status}',
        statusCode: '${res.status}',
      );
    }
    final data = res.data;
    final codes = (data is Map ? data['codes'] : null) as List?;
    return codes?.map((e) => e.toString()).toList() ?? const [];
  }

  /// Verifica un código de recuperación. Si es válido, la Edge Function
  /// elimina los factores MFA del usuario. Refresca la sesión para que el
  /// AAL se reevalúe (ya no se requiere AAL2).
  Future<void> verifyRecoveryCode(String code) async {
    final res = await _client.functions.invoke(
      'mfa-recovery',
      body: {'action': 'verify', 'code': code},
    );
    if (res.status != 200) {
      throw AuthException(
        'mfa-recovery verify returned ${res.status}',
        statusCode: '${res.status}',
      );
    }
    await _client.auth.refreshSession();
  }
}
