// Check: uploads "pending" sin confirmar y mas de 1h de antiguedad.
//
// Origen: el flow de PR-A es en 2 pasos -- (1) request_upload_url
// crea la fila con confirmed_at=null, (2) confirm_upload la marca.
// Si el cliente abandona entre paso 1 y 2 (cerro pestanya, error de
// red), la fila queda huerfana. RLS la oculta de la lista del cliente
// pero el object si esta en Storage consumiendo espacio.
//
// Severity: medium si hay > 10 huerfanos. Indica cron de purga faltante.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();

  const { count, error } = await admin
    .from("uploads")
    .select("id", { count: "exact", head: true })
    .is("confirmed_at", null)
    .lt("created_at", cutoff);

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "uploads.orphan_pending failed",
      severity: "info",
      impact: "Could not query orphan pending uploads.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const orphans = count ?? 0;
  if (orphans === 0) return [];

  const severity = orphans > 100 ? "high" : orphans > 10 ? "medium" : "low";

  return [{
    check_id: "uploads.orphan_pending",
    title: `${orphans} orphan pending upload(s) (> 1h old)`,
    severity,
    impact:
      "These rows leak Storage capacity (objects exist with no row "
      + "linking them visibly to a user). Over time, accumulates cost.",
    recommendation:
      "Run `select purge_pending_uploads(interval '1 hour');` to "
      + "clean them. Set up a cron job (pg_cron or external scheduler) "
      + "to call this RPC hourly.",
    affected_count: orphans,
  }];
};
