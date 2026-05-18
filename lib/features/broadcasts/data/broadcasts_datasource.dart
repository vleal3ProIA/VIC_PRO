import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/broadcast.dart';

/// Acceso a broadcasts. Lectura via RLS (admin), envío via Edge
/// Function `broadcast-dispatch`.
class BroadcastsDataSource {
  const BroadcastsDataSource(this._client);

  final SupabaseClient _client;

  /// Lista todos los broadcasts (drafts + sending + sent + failed),
  /// ordenados por fecha desc.
  Future<List<Broadcast>> list({int limit = 100}) async {
    final data = await _client
        .from('broadcasts')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Broadcast.fromMap)
        .toList(growable: false);
  }

  /// Detalle de un broadcast (mismo schema que list, pero por id).
  Future<Broadcast> get(String id) async {
    final data =
        await _client.from('broadcasts').select().eq('id', id).single();
    return Broadcast.fromMap(data);
  }

  /// Estima la audiencia ANTES de enviar. Devuelve count + by_locale.
  Future<BroadcastEstimate> estimate({
    required BroadcastTargetType targetType,
    required Map<String, dynamic> targetValue,
  }) async {
    final data = await _client.rpc<dynamic>(
      'admin_broadcast_estimate',
      params: {
        'p_target_type': targetType.dbValue,
        'p_target_value': targetValue,
      },
    );
    return BroadcastEstimate.fromMap(
      (data as Map).cast<String, dynamic>(),
    );
  }

  /// Envía un test al email indicado SIN crear row en broadcasts.
  Future<BroadcastActionResult> sendTest({
    required String subject,
    required String bodyHtml,
    required String toEmail,
    required String locale,
  }) async {
    return _invoke({
      'action': 'test',
      'subject': subject,
      'body_html': bodyHtml,
      'to_email': toEmail,
      'locale': locale,
    });
  }

  /// Crea el broadcast y arranca el envío. Devuelve `broadcast_id`
  /// para que la UI navegue al detail y empiece a pollear.
  Future<BroadcastActionResult> start({
    required String subject,
    required String bodyHtml,
    required BroadcastTargetType targetType,
    required Map<String, dynamic> targetValue,
  }) async {
    return _invoke({
      'action': 'start',
      'subject': subject,
      'body_html': bodyHtml,
      'target_type': targetType.dbValue,
      'target_value': targetValue,
    });
  }

  /// Borra un broadcast. Solo permitido para drafts y sent — los
  /// `sending` están en curso y no deben tocarse para evitar leak.
  Future<void> delete(String id) async {
    await _client.from('broadcasts').delete().eq('id', id);
  }

  Future<BroadcastActionResult> _invoke(Map<String, dynamic> body) async {
    try {
      final res =
          await _client.functions.invoke('broadcast-dispatch', body: body);
      final data = res.data;
      if (data is! Map) {
        return const BroadcastActionResult(ok: false, error: 'empty_response');
      }
      final payload = data.cast<String, dynamic>();
      return BroadcastActionResult(
        ok: payload['ok'] == true,
        broadcastId: payload['broadcast_id'] as String?,
        recipientsTotal: (payload['recipients_total'] as num?)?.toInt(),
        logId: payload['log_id'] as String?,
        error: payload['error'] as String?,
        detail: payload['detail'] as String?,
      );
    } on FunctionException catch (e) {
      // PR-E: extraer el code del body si la edge function lo devolvio
      // estructurado (ej. body_html_empty_after_sanitize, missing_fields,
      // invalid_target_type). Asi el snack muestra el motivo real en
      // vez de un generico "http_400".
      final details = e.details;
      if (details is Map) {
        final m = details.cast<String, dynamic>();
        final code = m['error'] as String?;
        if (code != null) {
          return BroadcastActionResult(
            ok: false,
            error: code,
            detail: m['detail'] as String?,
          );
        }
      }
      return BroadcastActionResult(ok: false, error: 'http_${e.status}');
    } catch (_) {
      return const BroadcastActionResult(ok: false, error: 'unknown');
    }
  }
}

class BroadcastActionResult {
  const BroadcastActionResult({
    required this.ok,
    this.broadcastId,
    this.recipientsTotal,
    this.logId,
    this.error,
    this.detail,
  });
  final bool ok;
  final String? broadcastId;
  final int? recipientsTotal;
  final String? logId;
  final String? error;
  final String? detail;
}
