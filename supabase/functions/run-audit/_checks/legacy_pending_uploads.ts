// Check: uploads confirmados con magic_validated=false. Son uploads
// pre-PR-A (backfill marco confirmed_at=created_at + magic_validated
// queda false por default). NO se valido nada en su momento; el riesgo
// es bajo (probablemente eran archivos legitimos) pero deja deuda
// documentada.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const { count, error } = await admin
    .from("uploads")
    .select("id", { count: "exact", head: true })
    .eq("magic_validated", false)
    .not("confirmed_at", "is", null)
    .is("deleted_at", null);

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "uploads.legacy_no_magic failed",
      severity: "info",
      impact: "Could not query legacy uploads.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const legacy = count ?? 0;
  if (legacy === 0) return [];

  return [{
    check_id: "uploads.legacy_no_magic",
    title: `${legacy} legacy upload(s) without magic bytes validation`,
    severity: "low",
    impact:
      "These files were uploaded before PR-A whitelist + magic bytes "
      + "validation was deployed. They may not match their declared "
      + "MIME type. Low risk because they predate the whitelist, but "
      + "informational.",
    recommendation:
      "Optionally, run a background job to revalidate them: for each "
      + "upload, download first 64KB, validate magic bytes against "
      + "mime_type. Mark `magic_validated=true` or soft-delete if "
      + "mismatch. Not urgent.",
    affected_count: legacy,
  }];
};
