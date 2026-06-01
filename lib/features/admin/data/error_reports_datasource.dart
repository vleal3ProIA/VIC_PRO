// ============================================================================
// admin · data/error_reports_datasource.dart · CRUD del pipeline /admin/errors
// ----------------------------------------------------------------------------
// Acceso directo a la tabla `public.error_reports` via supabase_flutter:
//
//   - list(status, severity)  -> select con filtros server-side
//   - get(id)                  -> select uno
//   - updateStatus(id, status, notes) -> marcar resuelto / en curso / etc.
//   - delete(id)               -> borrado definitivo
//   - diagnose(id, force)      -> invoca EF `diagnose-error` (cachea result)
//
// La RLS de 0082 ya bloquea el acceso a non-admin (no hay defensa cliente
// extra). El detalle del error que ve el admin SI incluye stack/proveedor --
// es justamente el lugar donde queremos verlo.
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/error_report.dart';

class ErrorReportsDataSource {
  const ErrorReportsDataSource(this._client);
  final SupabaseClient _client;

  /// Lista filtrada por estado y/o severidad. Los filtros se aplican
  /// server-side via .eq() de PostgREST (RLS aplica encima).
  Future<List<ErrorReport>> list({
    ErrorReportStatus? status,
    ErrorReportSeverity? severity,
    int limit = 100,
  }) async {
    var q = _client.from('error_reports').select();
    if (status != null) q = q.eq('status', status.wire);
    if (severity != null) q = q.eq('severity', severity.name);
    final data = await q.order('created_at', ascending: false).limit(limit);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(ErrorReport.fromMap)
        .toList(growable: false);
  }

  Future<ErrorReport?> get(String id) async {
    final data = await _client
        .from('error_reports')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return ErrorReport.fromMap(data);
  }

  /// Marca como resuelto (o cualquier otro estado) con notas opcionales.
  /// El campo `resolved_at` lo seteamos client-side (no hay trigger en
  /// 0082) -- solo para 'resolved'.
  Future<void> updateStatus({
    required String id,
    required ErrorReportStatus status,
    String? notes,
  }) async {
    final patch = <String, dynamic>{
      'status': status.wire,
      if (notes != null && notes.trim().isNotEmpty) 'resolution_notes': notes.trim(),
    };
    if (status == ErrorReportStatus.resolved) {
      patch['resolved_at'] = DateTime.now().toUtc().toIso8601String();
      final uid = _client.auth.currentUser?.id;
      if (uid != null) patch['resolved_by'] = uid;
    }
    await _client.from('error_reports').update(patch).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('error_reports').delete().eq('id', id);
  }

  /// Invoca la EF `diagnose-error`. Devuelve el AiDiagnosis ya parseado.
  /// Si la EF devolvio cache, `cached` viene `true`; la UI puede mostrar
  /// un hint pero NO es critico.
  Future<({AiDiagnosis diagnosis, bool cached})> diagnose(
    String errorId, {
    bool force = false,
  }) async {
    final res = await _client.functions.invoke(
      'diagnose-error',
      body: {'error_id': errorId, if (force) 'force': true},
    );
    final data = res.data;
    if (data is! Map) {
      throw const _DiagnoseFailed();
    }
    final payload = data.cast<String, dynamic>();
    final ok = payload['ok'];
    final diag = payload['diagnosis'];
    if (ok != true || diag is! Map) {
      throw const _DiagnoseFailed();
    }
    return (
      diagnosis: AiDiagnosis.fromMap(diag.cast<String, dynamic>()),
      cached: payload['cached'] == true,
    );
  }
}

/// Marker excepcion para que la UI muestre un mensaje generico SIN filtrar
/// detalle. No exponemos el contenido especifico.
class _DiagnoseFailed implements Exception {
  const _DiagnoseFailed();
}
