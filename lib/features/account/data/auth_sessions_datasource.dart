import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_session.dart';

/// Lee/revoca sesiones del usuario actual. Toda la lógica está
/// encapsulada en la Edge Function `account-sessions` — el cliente solo
/// pasa el JWT.
class AuthSessionsDataSource {
  const AuthSessionsDataSource(this._client);

  final SupabaseClient _client;

  Future<List<AuthSession>> list() async {
    final payload = await _invoke({'action': 'list'});
    final rows = (payload['sessions'] as List?) ?? const [];
    return rows
        .cast<Map<String, dynamic>>()
        .map(AuthSession.fromMap)
        .toList(growable: false);
  }

  /// Revoca una sesión. Si era la actual, el llamador es responsable de
  /// observar la respuesta `wasCurrent` y redirigir a login.
  Future<({bool wasCurrent})> revoke(String sessionId) async {
    final payload = await _invoke({
      'action': 'revoke',
      'session_id': sessionId,
    });
    return (wasCurrent: payload['was_current'] as bool? ?? false);
  }

  /// Cierra todas las demás sesiones. Devuelve el número de sesiones
  /// revocadas (info útil para el toast).
  Future<int> revokeOthers() async {
    final payload = await _invoke({'action': 'revoke_others'});
    return (payload['revoked_count'] as int?) ?? 0;
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(
        'account-sessions',
        body: body,
      );
      final data = res.data;
      if (data is! Map) {
        throw const AuthSessionsException('empty_response');
      }
      final payload = data.cast<String, dynamic>();
      if (payload['error'] != null) {
        throw AuthSessionsException(payload['error'] as String);
      }
      return payload;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        final m = details.cast<String, dynamic>();
        final code = m['error'] as String?;
        if (code != null) throw AuthSessionsException(code);
      }
      throw AuthSessionsException('http_${e.status}');
    }
  }
}

class AuthSessionsException implements Exception {
  const AuthSessionsException(this.code);
  final String code;
  @override
  String toString() => 'AuthSessionsException($code)';
}
