// ============================================================================
// Audit Center · Domain (PR-Audit-3)
// ----------------------------------------------------------------------------
// Modelos inmutables que matchean la estructura JSONB devuelta por las
// RPCs `admin_audit_reports_list` y `admin_audit_report_detail` y el
// formato que persiste la Edge Function `run-audit` en
// `audit_reports.findings`.
//
// **Por que NO sealed/freezed**: el resto del codebase usa clases planas
// `@immutable` con `factory fromMap` -- mantenemos consistencia.
// ============================================================================

import 'package:meta/meta.dart';

/// Severidad de un finding. Mapea 1:1 con `AuditSeverity` de
/// `supabase/functions/run-audit/_checks/_types.ts`.
///
/// **Orden visual**: critical > high > medium > low > info. Lo usamos
/// para ordenar findings y para asignar colores/iconos.
enum AuditSeverity {
  critical,
  high,
  medium,
  low,
  info;

  /// Devuelve la severity correspondiente al string del backend.
  /// Cualquier valor desconocido cae a `info` (conservador -- mejor
  /// mostrar de menos que crashear el detail page por un valor nuevo).
  static AuditSeverity fromString(String? raw) {
    switch (raw) {
      case 'critical':
        return AuditSeverity.critical;
      case 'high':
        return AuditSeverity.high;
      case 'medium':
        return AuditSeverity.medium;
      case 'low':
        return AuditSeverity.low;
      case 'info':
        return AuditSeverity.info;
      default:
        return AuditSeverity.info;
    }
  }

  /// Orden numerico para ordenar findings (critical primero).
  /// No usamos `index` directo por si reorganizamos el enum.
  int get rank => switch (this) {
        AuditSeverity.critical => 0,
        AuditSeverity.high => 1,
        AuditSeverity.medium => 2,
        AuditSeverity.low => 3,
        AuditSeverity.info => 4,
      };
}

/// Estado del ciclo de vida de un report. Mapea a la columna
/// `audit_reports.status` (CHECK constraint).
enum AuditReportStatus {
  running,
  completed,
  failed;

  static AuditReportStatus fromString(String? raw) {
    switch (raw) {
      case 'running':
        return AuditReportStatus.running;
      case 'completed':
        return AuditReportStatus.completed;
      case 'failed':
        return AuditReportStatus.failed;
      default:
        // Si el backend introduce un nuevo estado, tratamos como
        // 'running' para que la UI siga el polling y muestre lo que
        // tenga.
        return AuditReportStatus.running;
    }
  }
}

/// Un hallazgo dentro de un report. Estructura definida en
/// `_checks/_types.ts`:
///   { check_id, title, severity, impact, recommendation,
///     affected_count, details? }
@immutable
class AuditFinding {
  const AuditFinding({
    required this.checkId,
    required this.title,
    required this.severity,
    required this.impact,
    required this.recommendation,
    required this.affectedCount,
    this.details,
  });

  factory AuditFinding.fromMap(Map<String, dynamic> m) {
    return AuditFinding(
      checkId: m['check_id'] as String? ?? 'unknown',
      title: m['title'] as String? ?? '',
      severity: AuditSeverity.fromString(m['severity'] as String?),
      impact: m['impact'] as String? ?? '',
      recommendation: m['recommendation'] as String? ?? '',
      affectedCount: (m['affected_count'] as num?)?.toInt() ?? 0,
      details: (m['details'] is Map)
          ? (m['details'] as Map).cast<String, dynamic>()
          : null,
    );
  }

  /// Id estable del check que produjo el finding (ej. `rls.coverage`).
  /// Util para tests / filtrado.
  final String checkId;

  /// Titulo legible -- aparece como header de la card del finding.
  final String title;

  final AuditSeverity severity;

  /// Por que importa (parrafo breve).
  final String impact;

  /// Que deberia hacer el admin (parrafo breve, normalmente con pasos
  /// 1) 2) 3) en el texto).
  final String recommendation;

  /// Numero de filas / entidades afectadas. `0` si el finding es
  /// puramente informativo (ej. `audit.check_failed`).
  final int affectedCount;

  /// Datos adicionales libres. Cada check decide su forma -- ej.
  /// `{ tables: ['x', 'y'] }` o `{ tokens: [...] }`. Lo mostramos como
  /// JSON pretty-printed expandible en la UI.
  final Map<String, dynamic>? details;
}

/// Resumen agregado del report. Aparece en la lista (sin findings
/// detallados, solo counts). Estructura escrita por `run-audit`:
///   { by_severity: {critical, high, medium, low, info},
///     total_checks_run, total_findings, duration_ms, version }
@immutable
class AuditReportSummary {
  const AuditReportSummary({
    required this.bySeverity,
    required this.totalChecksRun,
    required this.totalFindings,
    required this.durationMs,
    this.version,
  });

  factory AuditReportSummary.empty() => const AuditReportSummary(
        bySeverity: <AuditSeverity, int>{},
        totalChecksRun: 0,
        totalFindings: 0,
        durationMs: 0,
      );

  factory AuditReportSummary.fromMap(Map<String, dynamic> m) {
    final raw = (m['by_severity'] is Map)
        ? (m['by_severity'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final bySev = <AuditSeverity, int>{};
    for (final sev in AuditSeverity.values) {
      bySev[sev] = (raw[sev.name] as num?)?.toInt() ?? 0;
    }
    return AuditReportSummary(
      bySeverity: bySev,
      totalChecksRun: (m['total_checks_run'] as num?)?.toInt() ?? 0,
      totalFindings: (m['total_findings'] as num?)?.toInt() ?? 0,
      durationMs: (m['duration_ms'] as num?)?.toInt() ?? 0,
      version: m['version'] as String?,
    );
  }

  final Map<AuditSeverity, int> bySeverity;
  final int totalChecksRun;
  final int totalFindings;
  final int durationMs;
  final String? version;

  /// Lectura segura: 0 si no hay info de esa severity.
  int count(AuditSeverity sev) => bySeverity[sev] ?? 0;

  /// `true` si hay al menos un finding critical o high. Lo usamos
  /// para colorear la card del report en la lista (rojo / verde).
  bool get hasSevereFindings => count(AuditSeverity.critical) > 0 ||
      count(AuditSeverity.high) > 0;
}

/// Resumen ligero devuelto por `admin_audit_reports_list` (SIN findings
/// detallados). Lo que aparece en la lista de la page /admin/audit.
@immutable
class AuditReportSummaryRow {
  const AuditReportSummaryRow({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.summary,
    this.finishedAt,
    this.triggeredBy,
  });

  factory AuditReportSummaryRow.fromMap(Map<String, dynamic> m) {
    return AuditReportSummaryRow(
      id: m['id'] as String,
      startedAt: DateTime.parse(m['started_at'] as String),
      finishedAt: m['finished_at'] != null
          ? DateTime.parse(m['finished_at'] as String)
          : null,
      status: AuditReportStatus.fromString(m['status'] as String?),
      summary: AuditReportSummary.fromMap(
        (m['summary'] is Map)
            ? (m['summary'] as Map).cast<String, dynamic>()
            : <String, dynamic>{},
      ),
      triggeredBy: m['triggered_by'] as String?,
    );
  }

  final String id;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final AuditReportStatus status;
  final AuditReportSummary summary;
  final String? triggeredBy;

  /// Duracion calculada si tenemos finished_at, sino null (esta en
  /// curso o fallo sin marcar fin). En la UI mostramos "running..."
  /// para esos casos.
  Duration? get duration {
    final end = finishedAt;
    if (end == null) return null;
    return end.difference(startedAt);
  }
}

/// Report completo (con findings) devuelto por
/// `admin_audit_report_detail` como JSONB (`to_jsonb(r.*)`).
@immutable
class AuditReport {
  const AuditReport({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.summary,
    required this.findings,
    this.finishedAt,
    this.triggeredBy,
    this.error,
  });

  factory AuditReport.fromMap(Map<String, dynamic> m) {
    final rawFindings = m['findings'];
    final List<AuditFinding> findings;
    if (rawFindings is List) {
      findings = rawFindings
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => AuditFinding.fromMap(e.cast<String, dynamic>()))
          .toList(growable: false);
    } else {
      findings = const <AuditFinding>[];
    }
    return AuditReport(
      id: m['id'] as String,
      startedAt: DateTime.parse(m['started_at'] as String),
      finishedAt: m['finished_at'] != null
          ? DateTime.parse(m['finished_at'] as String)
          : null,
      status: AuditReportStatus.fromString(m['status'] as String?),
      summary: AuditReportSummary.fromMap(
        (m['summary'] is Map)
            ? (m['summary'] as Map).cast<String, dynamic>()
            : <String, dynamic>{},
      ),
      findings: findings,
      triggeredBy: m['triggered_by'] as String?,
      error: m['error'] as String?,
    );
  }

  final String id;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final AuditReportStatus status;
  final AuditReportSummary summary;
  final List<AuditFinding> findings;
  final String? triggeredBy;

  /// Solo poblado si `status == failed`. Truncado a 500 chars en BD.
  final String? error;

  /// Devuelve findings agrupados por severity, en el orden critical ->
  /// info. Cada grupo conserva el orden original de `findings` (que es
  /// el orden en que los checks emitieron, util para trazabilidad).
  Map<AuditSeverity, List<AuditFinding>> findingsBySeverity() {
    final result = <AuditSeverity, List<AuditFinding>>{
      for (final s in AuditSeverity.values) s: <AuditFinding>[],
    };
    for (final f in findings) {
      result[f.severity]!.add(f);
    }
    return result;
  }

  Duration? get duration {
    final end = finishedAt;
    if (end == null) return null;
    return end.difference(startedAt);
  }
}
