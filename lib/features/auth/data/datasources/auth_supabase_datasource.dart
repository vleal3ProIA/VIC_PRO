import 'package:supabase_flutter/supabase_flutter.dart';

/// DataSource fino sobre el SDK de Supabase para auth.
/// El mapeo a `AuthFailure` se hace en el repositorio.
class AuthSupabaseDataSource {
  const AuthSupabaseDataSource(this._client);

  final SupabaseClient _client;

  /// `redirectTo` es la URL absoluta a la que Supabase devolverá al usuario
  /// tras pulsar el botón del email de verificación. En web debe estar en
  /// la lista de Redirect URLs del proyecto.
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
}
