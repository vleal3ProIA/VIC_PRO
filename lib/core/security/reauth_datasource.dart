import 'package:supabase_flutter/supabase_flutter.dart';

/// Datasource para la re-autenticacion con password (PR-F).
///
/// Llama a la Edge Function `verify-password` que valida la contrasena
/// del user actual y registra una verificacion en
/// `auth_recent_verifications`. Las Edge Functions destructivas
/// (delete-account, create-pat con scope write) consultan esa tabla
/// antes de actuar.
///
/// Flow tipico desde una pantalla:
///
/// ```dart
/// final ok = await ReauthDialog.show(
///   context,
///   actionKind: 'delete_account',
///   ref: ref,
/// );
/// if (ok != true) return; // user cancelo o password incorrecto
/// // ahora ya puedes invocar la accion destructiva server-side.
/// ```
class ReauthDataSource {
  const ReauthDataSource(this._client);

  final SupabaseClient _client;

  /// Verifica el [password] contra el user actual. Si OK, registra una
  /// verificacion en BD con [actionKind] que tendra validez 5 min.
  ///
  /// Devuelve [ReauthResult.success] o lanza [ReauthException] con el
  /// codigo del backend.
  Future<ReauthResult> verifyPassword({
    required String password,
    required String actionKind,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'verify-password',
        body: {
          'password': password,
          'action_kind': actionKind,
        },
      );
      final data = res.data;
      if (data is! Map) {
        throw const ReauthException('empty_response');
      }
      final payload = data.cast<String, dynamic>();
      if (payload['error'] != null) {
        throw ReauthException(payload['error'] as String);
      }
      final expiresAtRaw = payload['expires_at'] as String?;
      return ReauthResult(
        ok: payload['ok'] == true,
        expiresAt: expiresAtRaw != null ? DateTime.parse(expiresAtRaw) : null,
      );
    } on FunctionException catch (e) {
      // Extraer el code del body si la edge function lo devolvio
      // estructurado (invalid_password, rate_limited, etc.).
      final details = e.details;
      if (details is Map) {
        final m = details.cast<String, dynamic>();
        final code = m['error'] as String?;
        if (code != null) {
          throw ReauthException(code);
        }
      }
      throw ReauthException('http_${e.status}');
    }
  }
}

class ReauthResult {
  const ReauthResult({required this.ok, this.expiresAt});
  final bool ok;
  final DateTime? expiresAt;
}

class ReauthException implements Exception {
  const ReauthException(this.code);
  final String code;
  @override
  String toString() => 'ReauthException($code)';
}
