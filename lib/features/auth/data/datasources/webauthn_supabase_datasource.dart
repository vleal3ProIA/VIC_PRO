import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso fino al backend para las operaciones WebAuthn. Toda la lógica
/// criptográfica (verificación de firmas, generación de challenges) vive en
/// la Edge Function `webauthn`. Aquí solo se invoca esa función + lecturas
/// de la tabla `webauthn_credentials`.
class WebauthnSupabaseDataSource {
  const WebauthnSupabaseDataSource(this._client);

  final SupabaseClient _client;

  static const String _functionName = 'webauthn';
  static const String _table = 'webauthn_credentials';

  // ---- Edge Function calls -------------------------------------------------

  /// Pide al servidor el challenge + opciones de registro.
  /// Devuelve `{options: Map, challengeId: String}`.
  Future<Map<String, dynamic>> getRegistrationOptions() async {
    final res = await _client.functions.invoke(
      _functionName,
      body: {'action': 'register-options'},
    );
    _ensureOk(res, 'register-options');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Manda al servidor la respuesta del navegador para verificarla y
  /// guardar el passkey.
  Future<void> verifyRegistration({
    required String challengeId,
    required Map<String, dynamic> response,
    String? friendlyName,
  }) async {
    final res = await _client.functions.invoke(
      _functionName,
      body: {
        'action': 'register-verify',
        'challengeId': challengeId,
        'response': response,
        if (friendlyName != null) 'friendlyName': friendlyName,
      },
    );
    _ensureOk(res, 'register-verify');
  }

  /// Pide al servidor las opciones de autenticación (discoverable
  /// credentials — sin necesidad de saber qué usuario).
  Future<Map<String, dynamic>> getAuthenticationOptions() async {
    final res = await _client.functions.invoke(
      _functionName,
      body: {'action': 'auth-options'},
    );
    _ensureOk(res, 'auth-options');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Verifica la respuesta de autenticación. Devuelve `{tokenHash, email}`
  /// para que la app pueda canjearlo por una sesión Supabase real con
  /// `verifyMagicLinkToken`.
  Future<({String tokenHash, String email})> verifyAuthentication({
    required String challengeId,
    required Map<String, dynamic> response,
  }) async {
    final res = await _client.functions.invoke(
      _functionName,
      body: {
        'action': 'auth-verify',
        'challengeId': challengeId,
        'response': response,
      },
    );
    _ensureOk(res, 'auth-verify');
    final data = res.data as Map;
    return (
      tokenHash: data['tokenHash'] as String,
      email: data['email'] as String,
    );
  }

  /// Canjea el token de magic link (devuelto por `auth-verify`) por una
  /// sesión Supabase real.
  Future<AuthResponse> verifyMagicLinkToken(String tokenHash) {
    return _client.auth.verifyOTP(
      type: OtpType.magiclink,
      tokenHash: tokenHash,
    );
  }

  // ---- Reads / deletes -----------------------------------------------------

  /// Lista los passkeys del usuario actual (RLS limita a "los suyos").
  Future<List<Map<String, dynamic>>> listMyPasskeys() async {
    final data = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Borra un passkey por id. RLS impide borrar uno ajeno.
  Future<void> deletePasskey(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  // ---- Helpers -------------------------------------------------------------

  void _ensureOk(FunctionResponse res, String action) {
    if (res.status != 200) {
      final detail = res.data is Map ? (res.data as Map)['error'] : null;
      throw AuthException(
        'webauthn/$action returned ${res.status} ${detail ?? ''}'.trim(),
        statusCode: '${res.status}',
      );
    }
  }
}
