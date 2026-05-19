// Check: tables with RLS enabled but no policies defined.
//
// Resultado: tabla bloqueada total para roles `authenticated` y
// `anon`. Puede ser intencional (ej. audit log append-only que solo
// se toca via service_role), pero suele indicar policies olvidadas.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const { data, error } = await admin.rpc(
    "admin_audit_tables_no_policies",
  );

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "rls.no_policies failed",
      severity: "info",
      impact: "Could not enumerate tables with RLS but no policies.",
      recommendation: "Check migration 0040.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const tables = (data as Array<{ table_name: string }>) ?? [];
  if (tables.length === 0) return [];

  return [{
    check_id: "rls.no_policies",
    title: "Tables with RLS but no policies",
    severity: "medium",
    impact:
      "These tables are effectively inaccessible to regular users. "
      + "If this is unintentional, the feature using them is broken.",
    recommendation:
      "Review each table. If access from clients is expected, add "
      + "appropriate `create policy` statements. If write-only by "
      + "service_role (audit logs, etc.), this is fine -- document it.",
    affected_count: tables.length,
    details: { tables: tables.map((t) => t.table_name) },
  }];
};
