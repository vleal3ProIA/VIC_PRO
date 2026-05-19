// Check: uploads detectados como `suspicious` por VirusTotal en los
// ultimos 30 dias. Aunque el upload ya esta soft-deleted automatico
// (visible en /admin), es util para el admin tener un dashboard de
// "cuanta gente intenta subir malware". Si > 5 en un mes podria
// indicar abuso coordinado.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const cutoff =
    new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

  const { count, error } = await admin
    .from("uploads")
    .select("id", { count: "exact", head: true })
    .eq("virus_scan_status", "suspicious")
    .gte("virus_scan_at", cutoff);

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "uploads.suspicious_recent failed",
      severity: "info",
      impact: "Could not query suspicious uploads.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const detected = count ?? 0;
  if (detected === 0) return [];

  // Severity: high siempre que haya >= 1 -- significa que alguien
  // intento subir malware (incluso si el sistema lo bloqueo).
  const severity = detected >= 10 ? "high" : "medium";

  return [{
    check_id: "uploads.suspicious_recent",
    title: `${detected} suspicious upload(s) detected in the last 30 days`,
    severity,
    impact:
      "VirusTotal flagged these files as malicious. The system "
      + "soft-deleted them automatically, but the users who uploaded "
      + "them may need investigation (compromised account, abuse).",
    recommendation:
      "Review the affected uploads via SQL: "
      + "`select id, user_id, filename, virus_scan_result->'flagged_engines' "
      + "from uploads where virus_scan_status='suspicious' "
      + "and virus_scan_at > now() - interval '30 days';`. "
      + "Consider banning users with multiple detections.",
    affected_count: detected,
  }];
};
