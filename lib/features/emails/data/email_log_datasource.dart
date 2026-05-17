import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/email_log_entry.dart';

/// Acceso a `email_log`. Lecturas via RLS (admin-only). Test ping
/// llama a `send-email` Edge Function con `type=test`.
class EmailLogDataSource {
  const EmailLogDataSource(this._client);

  final SupabaseClient _client;

  /// Lista los últimos N emails. Admin-only via RLS.
  Future<List<EmailLogEntry>> list({int limit = 100}) async {
    final data = await _client
        .from('email_log')
        .select(
          'id, type, to_email, to_user_id, locale, subject, status, '
          'error, provider, meta, sent_at, created_at',
        )
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(EmailLogEntry.fromMap)
        .toList(growable: false);
  }

  /// Envía un email de prueba a la dirección dada. Admin-only.
  /// Devuelve la respuesta cruda de la Edge Function — la UI lo
  /// muestra como snackbar.
  Future<TestEmailResult> sendTest({
    required String to,
    required String locale,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'send-email',
        body: {
          'type': 'test',
          'to': to,
          'locale': locale,
          'data': {
            'sent_at': DateTime.now().toUtc().toIso8601String(),
          },
        },
      );
      final data = res.data;
      if (data is! Map) {
        return const TestEmailResult(ok: false, error: 'empty_response');
      }
      final payload = data.cast<String, dynamic>();
      return TestEmailResult(
        ok: payload['ok'] == true,
        error: payload['error'] as String?,
        logId: payload['log_id'] as String?,
      );
    } on FunctionException catch (e) {
      return TestEmailResult(ok: false, error: 'http_${e.status}');
    } catch (_) {
      return const TestEmailResult(ok: false, error: 'unknown');
    }
  }
}

class TestEmailResult {
  const TestEmailResult({required this.ok, this.error, this.logId});
  final bool ok;
  final String? error;
  final String? logId;
}
