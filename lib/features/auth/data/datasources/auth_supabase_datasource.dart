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
}
