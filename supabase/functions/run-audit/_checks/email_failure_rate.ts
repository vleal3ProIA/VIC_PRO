// Check: tasa de fallos del email_log en los ultimos 7 dias. Si
// > 20% suele indicar problema serio (SMTP credentials, dominio en
// blacklist, rate limit del proveedor).

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const { data, error } = await admin
    .rpc("admin_audit_email_failure_rate", { p_days: 7 })
    .maybeSingle();

  if (error || !data) {
    return [{
      check_id: "audit.check_failed",
      title: "emails.failure_rate failed",
      severity: "info",
      impact: "Could not compute email failure rate.",
      recommendation: "Check migration 0040.",
      affected_count: 0,
      details: { error: error?.message },
    }];
  }

  const total = (data.total ?? 0) as number;
  const failed = (data.failed ?? 0) as number;
  const ratePct = Number(data.rate_pct ?? 0);

  // Si total < 10 no hay muestra suficiente. No reportamos.
  if (total < 10) return [];
  // Si tasa < 5% es ruido normal (bounces ocasionales). No reportamos.
  if (ratePct < 5) return [];

  const severity = ratePct >= 50
    ? "critical"
    : ratePct >= 20
    ? "high"
    : "medium";

  return [{
    check_id: "emails.failure_rate",
    title:
      `${ratePct}% of emails failed in the last 7 days `
      + `(${failed}/${total})`,
    severity,
    impact:
      "A high rate of email failures means users are not receiving "
      + "signup confirmations, password resets, magic links, etc. "
      + "Activation and recovery flows are broken.",
    recommendation:
      "1) Check `SMTP_*` secrets are correctly configured. "
      + "2) Verify SPF/DKIM/DMARC records on your sending domain. "
      + "3) Check SMTP provider dashboard for rate limit or block. "
      + "4) Review `email_log` errors for patterns: "
      + "`select error, count(*) from email_log "
      + "where status='failed' group by error order by count desc;`",
    affected_count: failed,
    details: { total, failed, rate_pct: ratePct },
  }];
};
