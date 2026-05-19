// ============================================================================
// Tipos comunes para los checks de Audit Center (PR-Audit-2)
// ----------------------------------------------------------------------------
// Cada check exporta una funcion `runCheck(admin)` que devuelve un
// array de `AuditFinding`. El runner los acumula y guarda en
// `audit_reports.findings`.
//
// **Filosofia**: cada check es independiente, sin side effects salvo
// queries de lectura. Si un check necesita writes, va por su propio
// path (no como check). Los checks pueden fallar -- el runner los
// envuelve en try/catch y registra el error como finding
// `audit.check_failed`.
// ============================================================================

export type AuditSeverity =
  | "critical"
  | "high"
  | "medium"
  | "low"
  | "info";

export interface AuditFinding {
  check_id: string;
  title: string;
  severity: AuditSeverity;
  impact: string;
  recommendation: string;
  affected_count: number;
  details?: Record<string, unknown>;
}

/// Cada check exporta esta funcion. Recibe el admin client
/// (service_role, bypassa RLS) y devuelve findings detectados.
///
/// **Contract**:
/// - Si NO hay problemas: devolver `[]` (array vacio).
/// - Si hay problemas: devolver 1+ findings con la info estructurada.
/// - NO lanzar -- en error de query, devolver un finding `severity:
///   'info'` con el detalle.
// deno-lint-ignore no-explicit-any
export type AuditCheckRunner = (admin: any) => Promise<AuditFinding[]>;
