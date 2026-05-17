import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/personal_access_token.dart';

/// Acceso a Personal Access Tokens. Las lecturas/revocaciones van
/// directas vIa RLS y RPC; la creación pasa por la Edge Function
/// `create-pat` porque genera el secret server-side y lo devuelve
/// una sola vez.
class TokensDataSource {
  const TokensDataSource(this._client);

  final SupabaseClient _client;

  /// Listado de tokens del usuario, los activos primero y dentro de
  /// cada grupo más recientes arriba.
  Future<List<PersonalAccessToken>> list() async {
    final data = await _client
        .from('personal_access_tokens')
        .select(
          'id, name, prefix, scopes, expires_at, last_used_at, '
          'revoked_at, created_at',
        )
        .order('revoked_at', ascending: true, nullsFirst: true)
        .order('created_at', ascending: false);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(PersonalAccessToken.fromMap)
        .toList(growable: false);
  }

  /// Crea un PAT y devuelve el objeto con [PersonalAccessToken.secret]
  /// poblado. ES LA UNICA VEZ que el secret será visible -- la UI
  /// debe mostrarlo en un dialog con botón "copiar" y advertencia.
  ///
  /// Throws [TokenException] con `code` (`invalid_name`, `invalid_scope`,
  /// `rate_limited`, etc.) si el backend rechaza.
  Future<PersonalAccessToken> create({
    required String name,
    List<String> scopes = const ['read'],
    int? expiresInDays,
  }) async {
    final payload = await _invoke({
      'name': name,
      'scopes': scopes,
      if (expiresInDays != null) 'expires_in_days': expiresInDays,
    });
    return PersonalAccessToken.fromMap(payload);
  }

  /// Marca el token como revocado (`revoked_at = now()`). Idempotente.
  /// Devuelve `true` si efectivamente cambió el estado (era activo).
  Future<bool> revoke(String tokenId) async {
    final result = await _client.rpc<dynamic>(
      'revoke_personal_access_token',
      params: {'p_id': tokenId},
    );
    return result == true;
  }

  /// Borra el token DEFINITIVAMENTE (admin only). Para usuarios
  /// normales se prefiere [revoke] para mantener el audit trail.
  Future<void> delete(String tokenId) async {
    await _client.from('personal_access_tokens').delete().eq('id', tokenId);
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('create-pat', body: body);
      final data = res.data;
      if (data is! Map) {
        throw const TokenException('empty_response');
      }
      final payload = data.cast<String, dynamic>();
      if (payload['error'] != null) {
        throw TokenException(
          payload['error'] as String,
          detail: payload['detail'] as String?,
        );
      }
      return payload;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        final m = details.cast<String, dynamic>();
        final code = m['error'] as String?;
        if (code != null) {
          throw TokenException(code, detail: m['detail'] as String?);
        }
      }
      throw TokenException('http_${e.status}');
    }
  }
}

class TokenException implements Exception {
  const TokenException(this.code, {this.detail});
  final String code;
  final String? detail;
  @override
  String toString() => detail == null
      ? 'TokenException($code)'
      : 'TokenException($code: $detail)';
}
