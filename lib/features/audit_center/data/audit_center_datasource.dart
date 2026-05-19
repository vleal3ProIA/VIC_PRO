// ============================================================================
// Audit Center · Data layer (PR-Audit-3)
// ----------------------------------------------------------------------------
// Acceso a las 3 superficies del backend:
//
// 1. `admin_audit_reports_list(p_limit)`   -> RPC: lista de N reports
//    recientes (sin findings detallados, solo el summary agregado).
// 2. `admin_audit_report_detail(p_id)`     -> RPC: report completo con
//    todos los findings.
// 3. Edge Function `run-audit`              -> dispara una nueva auditoria
//    en background. Devuelve `{ ok, report_id, queued }`.
//
// Las RPCs aplican `is_admin()` por su cuenta -- si el llamante no es
// admin, lanzan `admin only` que llega como `PostgrestException` al
// cliente. La Edge Function valida el JWT y el rol.
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/audit_report.dart';

/// Excepcion semantica para errores del runner. Mantenemos el codigo
/// crudo (`rate_limited`, `forbidden`, etc.) para que la UI lo pueda
/// mapear a un string traducido.
class AuditRunException implements Exception {
  const AuditRunException(this.code, {this.detail});
  final String code;
  final String? detail;

  @override
  String toString() => 'AuditRunException($code${detail != null ? ': $detail' : ''})';
}

/// Acceso de bajo nivel a Audit Center. Sin estado -- toda la cache la
/// gestiona Riverpod.
class AuditCenterDataSource {
  const AuditCenterDataSource(this._client);

  final SupabaseClient _client;

  /// Lista los N reports mas recientes. Default 20 (max 100 -- la RPC
  /// limita en el server).
  Future<List<AuditReportSummaryRow>> listReports({int limit = 20}) async {
    final data = await _client.rpc<dynamic>(
      'admin_audit_reports_list',
      params: {'p_limit': limit},
    );
    return (data as List)
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => AuditReportSummaryRow.fromMap(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Devuelve el report completo con findings.
  ///
  /// Si el id no existe lanza `PostgrestException` con
  /// `code = 'P0001'` y `message = 'report_not_found'`.
  Future<AuditReport> getReport(String id) async {
    final data = await _client.rpc<dynamic>(
      'admin_audit_report_detail',
      params: {'p_id': id},
    );
    if (data is! Map) {
      throw const AuditRunException('invalid_response');
    }
    return AuditReport.fromMap(data.cast<String, dynamic>());
  }

  /// Dispara la auditoria en background. Devuelve el id del report que
  /// ya tiene status='running' en BD -- la UI lo usa para hacer polling.
  ///
  /// Errores mapeados:
  ///   - 401 invalid_token       -> AuditRunException('invalid_token')
  ///   - 403 forbidden           -> AuditRunException('forbidden')
  ///   - 429 rate_limited        -> AuditRunException('rate_limited')
  ///   - 500 db_error / otros    -> AuditRunException('server_error')
  Future<String> startAudit() async {
    try {
      final res = await _client.functions.invoke('run-audit');
      final data = res.data;
      if (data is! Map) {
        throw const AuditRunException('invalid_response');
      }
      final payload = data.cast<String, dynamic>();
      if (payload['error'] != null) {
        throw AuditRunException(payload['error'] as String);
      }
      final id = payload['report_id'] as String?;
      if (id == null) {
        throw const AuditRunException('invalid_response');
      }
      return id;
    } on FunctionException catch (e) {
      // La SDK lanza FunctionException con `details` que suele incluir
      // el body del 4xx/5xx. Intentamos extraer el `error` campo.
      final details = e.details;
      if (details is Map) {
        final err = details['error'];
        if (err is String) {
          throw AuditRunException(err);
        }
      }
      throw AuditRunException(
        'server_error',
        detail: details?.toString(),
      );
    }
  }
}
