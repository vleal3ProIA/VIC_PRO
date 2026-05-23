// ============================================================================
// AI providers · Data layer (Fase 0)
// ----------------------------------------------------------------------------
// Invoca la Edge Function `ai-admin` (gateada por capability `manage_ai`). Es
// la ÚNICA puerta a la tabla solo-servidor `ai_credentials`: nunca recibe la
// api_key completa, solo metadatos + `key_last4`.
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ai_provider.dart';

/// Error semántico del endpoint ai-admin. `code` crudo para mapear a i18n.
class AiAdminException implements Exception {
  const AiAdminException(this.code, {this.detail});
  final String code;
  final String? detail;

  @override
  String toString() => 'AiAdminException($code)';
}

/// Resultado del `list`: proveedores + credenciales (sin keys).
class AiAdminData {
  const AiAdminData({required this.providers, required this.credentials});
  final List<AiProvider> providers;
  final List<AiCredential> credentials;

  List<AiCredential> credentialsFor(String providerId) => credentials
      .where((c) => c.providerId == providerId)
      .toList(growable: false);
}

/// Resultado de la acción `test` (no lanza: devuelve ok/detalle para la UI).
typedef AiTestResult = ({
  bool ok,
  String? model,
  String? sample,
  String? detail
});

class AiAdminDataSource {
  const AiAdminDataSource(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('ai-admin', body: body);
      final data = res.data;
      if (data is! Map) throw const AiAdminException('invalid_response');
      final payload = data.cast<String, dynamic>();
      if (payload['ok'] != true && payload['error'] != null) {
        throw AiAdminException(
          payload['error'] as String,
          detail: payload['detail'] as String?,
        );
      }
      return payload;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw AiAdminException(details['error'] as String);
      }
      throw AiAdminException('server_error', detail: details?.toString());
    }
  }

  Future<AiAdminData> list() async {
    final p = await _invoke({'action': 'list'});
    final provs = ((p['providers'] as List?) ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => AiProvider.fromMap(e.cast<String, dynamic>()))
        .toList(growable: false);
    final creds = ((p['credentials'] as List?) ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => AiCredential.fromMap(e.cast<String, dynamic>()))
        .toList(growable: false);
    return AiAdminData(providers: provs, credentials: creds);
  }

  Future<void> saveProvider({
    required String id,
    bool? enabled,
    int? priority,
    String? defaultModel,
    String? baseUrl,
  }) async {
    final body = <String, dynamic>{'action': 'save_provider', 'id': id};
    if (enabled != null) body['enabled'] = enabled;
    if (priority != null) body['priority'] = priority;
    if (defaultModel != null) body['default_model'] = defaultModel;
    if (baseUrl != null) body['base_url'] = baseUrl;
    await _invoke(body);
  }

  Future<void> addCredential({
    required String providerId,
    required String apiKey,
    String? label,
  }) async {
    await _invoke({
      'action': 'add_credential',
      'provider_id': providerId,
      'api_key': apiKey,
      'label': label,
    });
  }

  Future<void> updateCredential({
    required String id,
    bool? enabled,
    bool clearCooldown = false,
  }) async {
    final body = <String, dynamic>{'action': 'update_credential', 'id': id};
    if (enabled != null) body['enabled'] = enabled;
    if (clearCooldown) body['clear_cooldown'] = true;
    await _invoke(body);
  }

  Future<void> deleteCredential(String id) async {
    await _invoke({'action': 'delete_credential', 'id': id});
  }

  /// Hace una mini-llamada real para validar proveedor+key. No lanza: el
  /// backend responde 200 con `ok:false` + `detail` si falla.
  Future<AiTestResult> test(String providerId) async {
    try {
      final res = await _client.functions.invoke(
        'ai-admin',
        body: {'action': 'test', 'provider_id': providerId},
      );
      final data = res.data;
      if (data is! Map) {
        return (
          ok: false,
          model: null,
          sample: null,
          detail: 'invalid_response'
        );
      }
      final p = data.cast<String, dynamic>();
      return (
        ok: p['ok'] == true,
        model: p['model'] as String?,
        sample: p['sample'] as String?,
        detail: p['detail'] as String?,
      );
    } on FunctionException catch (e) {
      final d = e.details;
      final detail = (d is Map && d['detail'] is String)
          ? d['detail'] as String
          : d?.toString();
      return (ok: false, model: null, sample: null, detail: detail);
    }
  }
}
