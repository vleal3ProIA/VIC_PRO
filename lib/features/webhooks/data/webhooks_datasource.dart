import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/webhook_delivery.dart';
import '../domain/webhook_endpoint.dart';

/// Acceso a los webhooks salientes. Las lecturas usan RLS; la
/// creación, el test ping y la administración pasan por la Edge
/// Function `webhook-dispatch` (genera secret + hashea + dispara
/// POSTs).
class WebhooksDataSource {
  const WebhooksDataSource(this._client);

  final SupabaseClient _client;

  /// Lista los endpoints visibles para el user (suyos + de tenants
  /// en los que es miembro).
  Future<List<WebhookEndpoint>> listEndpoints() async {
    final data = await _client
        .from('webhook_endpoints')
        .select(
          'id, user_id, tenant_id, url, description, events, active, '
          'consecutive_failures, disabled_reason, created_at, updated_at',
        )
        .order('created_at', ascending: false);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(WebhookEndpoint.fromMap)
        .toList(growable: false);
  }

  /// Crea un endpoint nuevo y devuelve el objeto CON el secret raw.
  /// ES LA UNICA VEZ que el secret se ve.
  Future<WebhookEndpoint> createEndpoint({
    required String url,
    String? description,
    List<String> events = const ['*'],
    String? tenantId,
  }) async {
    final payload = await _invoke({
      'action': 'create_endpoint',
      'url': url,
      if (description != null && description.isNotEmpty)
        'description': description,
      'events': events,
      if (tenantId != null) 'tenant_id': tenantId,
    });
    return WebhookEndpoint.fromMap(payload);
  }

  /// Envía un ping de prueba al endpoint. Devuelve el resultado
  /// (`success` | `failed`) con http_status / error.
  Future<WebhookTestResult> sendTestPing(String endpointId) async {
    final payload = await _invoke({
      'action': 'test',
      'endpoint_id': endpointId,
    });
    return WebhookTestResult(
      success: (payload['status'] as String?) == 'success',
      httpStatus: (payload['http_status'] as num?)?.toInt(),
      error: payload['error'] as String?,
    );
  }

  /// Rota el HMAC secret de un endpoint existente. El secret viejo
  /// deja de funcionar inmediatamente -- futuros dispatchers firman
  /// con el nuevo. Devuelve el secret raw UNA SOLA VEZ; el caller
  /// debe enseyarlo al user inmediatamente (con copy-to-clipboard) y
  /// olvidarlo.
  ///
  /// **Pre-requisito**: la EF exige `consume_recent_verification(
  /// 'webhook_secret_rotate')`. El caller debe llamar primero a
  /// `ReauthDialog.show(actionKind: 'webhook_secret_rotate')`. Si no
  /// hay verificacion fresca, la EF devuelve `reauth_required` 403.
  Future<String> rotateSecret(String endpointId) async {
    final payload = await _invoke({
      'action': 'rotate_secret',
      'endpoint_id': endpointId,
    });
    final secret = payload['secret'] as String?;
    if (secret == null || secret.isEmpty) {
      throw const WebhookException('empty_response');
    }
    return secret;
  }

  /// Pausa o reanuda un endpoint. Si se reanuda, resetea el contador
  /// de fallos.
  Future<bool> setActive(String endpointId, {required bool active}) async {
    final result = await _client.rpc<dynamic>(
      'set_webhook_endpoint_active',
      params: {'p_id': endpointId, 'p_active': active},
    );
    return result == true;
  }

  /// Borra el endpoint definitivamente (cascade a deliveries +
  /// secret).
  Future<void> delete(String endpointId) async {
    await _client.from('webhook_endpoints').delete().eq('id', endpointId);
  }

  /// Lista los últimos N intentos para un endpoint. Para la vista
  /// de detalle "actividad reciente".
  Future<List<WebhookDelivery>> listDeliveries(
    String endpointId, {
    int limit = 50,
  }) async {
    final data = await _client
        .from('webhook_deliveries')
        .select(
          'id, endpoint_id, event_type, status, attempt, http_status, '
          'response_body, error, next_retry_at, created_at, '
          'delivered_at, failed_at',
        )
        .eq('endpoint_id', endpointId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(WebhookDelivery.fromMap)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(
        'webhook-dispatch',
        body: body,
      );
      final data = res.data;
      if (data is! Map) {
        throw const WebhookException('empty_response');
      }
      final payload = data.cast<String, dynamic>();
      if (payload['error'] != null) {
        throw WebhookException(
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
          throw WebhookException(code, detail: m['detail'] as String?);
        }
      }
      throw WebhookException('http_${e.status}');
    }
  }
}

class WebhookException implements Exception {
  const WebhookException(this.code, {this.detail});
  final String code;
  final String? detail;
  @override
  String toString() => detail == null
      ? 'WebhookException($code)'
      : 'WebhookException($code: $detail)';
}

/// Resultado del ping de test. Si `success = true`, el endpoint
/// devolvió 2xx; en otro caso `httpStatus` o `error` indican qué pasó.
class WebhookTestResult {
  const WebhookTestResult({
    required this.success,
    this.httpStatus,
    this.error,
  });

  final bool success;
  final int? httpStatus;
  final String? error;
}
