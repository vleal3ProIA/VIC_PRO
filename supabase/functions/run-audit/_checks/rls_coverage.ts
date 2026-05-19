// Check: tables in public schema without Row Level Security enabled.
//
// Severity: critical. Sin RLS, cualquier user autenticado puede leer
// y escribir cualquier fila a traves de PostgREST. Es el agujero mas
// grande posible en una app con Supabase.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const { data, error } = await admin.rpc(
    "admin_audit_tables_without_rls",
  );

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "rls.coverage failed",
      severity: "info",
      impact: "Could not enumerate tables without RLS.",
      recommendation: "Check that migration 0040 is applied.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const tables = (data as Array<{ table_name: string }>) ?? [];
  if (tables.length === 0) return [];

  return [{
    check_id: "rls.coverage",
    title: "Tables without Row Level Security",
    severity: "critical",
    impact:
      "Any authenticated user can read or write any row in these "
      + "tables via PostgREST. Major data exposure risk.",
    recommendation:
      "Run `alter table public.<name> enable row level security;` "
      + "on each affected table, then add appropriate policies.",
    affected_count: tables.length,
    details: { tables: tables.map((t) => t.table_name) },
  }];
};
