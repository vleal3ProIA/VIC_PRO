// Check: uploads con virus_scan_status='error' que llevan > 24h sin
// reintentarse. VirusTotal pudo estar caido o la API key vencida.
// Si > 0, el admin debe investigar y eventualmente re-disparar el
// scan manualmente.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const { count, error } = await admin
    .from("uploads")
    .select("id", { count: "exact", head: true })
    .eq("virus_scan_status", "error")
    .lt("virus_scan_at", cutoff);

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "uploads.scan_errors failed",
      severity: "info",
      impact: "Could not query failed virus scans.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const failed = count ?? 0;
  if (failed === 0) return [];

  return [{
    check_id: "uploads.scan_errors",
    title: `${failed} upload(s) with stuck virus scan errors (> 24h)`,
    severity: failed > 50 ? "high" : "low",
    impact:
      "Files were uploaded but VirusTotal scan never completed. "
      + "If VirusTotal was down or API key invalid, no protection was "
      + "applied -- the file may be malware.",
    recommendation:
      "1) Check `VIRUSTOTAL_API_KEY` is set and valid. "
      + "2) Manually re-scan the affected uploads (invoke `scan-upload` "
      + "Edge Function per upload_id). "
      + "3) Future: implement automatic retry with exponential backoff.",
    affected_count: failed,
  }];
};
