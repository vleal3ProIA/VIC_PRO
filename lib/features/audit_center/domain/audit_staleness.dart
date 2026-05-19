// ============================================================================
// Audit Center · Staleness helper (PR-Audit-4)
// ----------------------------------------------------------------------------
// Decide si el conjunto de reports en la UI esta "stale" (= demasiado
// viejo) y deberia mostrar un banner sugiriendo lanzar uno nuevo. Es
// una funcion pura para que sea trivial de testear y reusar.
//
// **Reglas**:
//   - Lista vacia                              -> NO stale (empty state
//     ya cubre el caso; no anyadimos doble mensaje).
//   - Mas reciente esta running                -> NO stale (algo se
//     esta haciendo, espera a que acabe).
//   - Mas reciente es completed y < 7 dias     -> NO stale.
//   - Mas reciente es completed y >= 7 dias    -> stale.
//   - Mas reciente esta failed                 -> stale (necesitamos
//     uno bueno para validar el estado).
//
// 7 dias es un umbral conservador: el cron diario lanza un audit cada
// 24h, asi que >7 dias significa que el cron ha fallado o no se ha
// configurado.
// ============================================================================

import 'audit_report.dart';

/// Resultado del check de staleness. Devolvemos un enum y los dias
/// transcurridos para que la UI pueda mostrar "Last audit was X days
/// ago" sin recalcular.
class AuditStaleness {
  const AuditStaleness({
    required this.isStale,
    required this.reason,
    this.daysSinceLast,
  });

  /// `true` si la UI debe mostrar el banner stale.
  final bool isStale;

  /// Razon textual (para el log o tooltip; no es para mostrar al user
  /// directamente -- la UI tiene strings propios localizados).
  final String reason;

  /// Dias enteros desde el ultimo audit completado. `null` si no hay
  /// ninguno o la lista esta vacia.
  final int? daysSinceLast;

  static const fresh = AuditStaleness(isStale: false, reason: 'fresh');
  static const noReports = AuditStaleness(isStale: false, reason: 'empty');
  static const running = AuditStaleness(
    isStale: false,
    reason: 'audit_running',
  );
}

/// Evalua si la lista de reports esta stale. `now` se puede inyectar
/// para hacer el test deterministico.
AuditStaleness evaluateAuditStaleness(
  List<AuditReportSummaryRow> reports, {
  DateTime? now,
  int staleThresholdDays = 7,
}) {
  if (reports.isEmpty) return AuditStaleness.noReports;

  // `reports` viene ordenado desc por started_at del backend (orden de
  // la RPC `admin_audit_reports_list`). El primer item es el mas
  // reciente.
  final latest = reports.first;
  if (latest.status == AuditReportStatus.running) {
    return AuditStaleness.running;
  }

  final reference = now ?? DateTime.now();
  // Para 'failed' usamos started_at -- finished_at puede no estar.
  // Para 'completed' tambien usamos started_at por consistencia (la
  // diferencia con finished_at es de segundos, irrelevante para
  // umbrales de dias).
  final daysSince =
      reference.toUtc().difference(latest.startedAt.toUtc()).inDays;

  if (latest.status == AuditReportStatus.failed) {
    return AuditStaleness(
      isStale: true,
      reason: 'last_failed',
      daysSinceLast: daysSince,
    );
  }

  if (daysSince >= staleThresholdDays) {
    return AuditStaleness(
      isStale: true,
      reason: 'too_old',
      daysSinceLast: daysSince,
    );
  }

  return AuditStaleness(
    isStale: false,
    reason: 'fresh',
    daysSinceLast: daysSince,
  );
}
