// Check: admins sin MFA. Cada admin es punto unico de compromiso del
// sistema entero. Si se pierde su password (phishing, credential
// stuffing), un atacante obtiene control admin.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const { data, error } = await admin
    .rpc("admin_audit_mfa_admin_coverage")
    .maybeSingle();

  if (error || !data) {
    return [{
      check_id: "audit.check_failed",
      title: "auth.mfa_admin_coverage failed",
      severity: "info",
      impact: "Could not compute admin MFA coverage.",
      recommendation: "Check migration 0040.",
      affected_count: 0,
      details: { error: error?.message },
    }];
  }

  const totalAdmins = (data.total_admins ?? 0) as number;
  const withoutMfa = (data.without_mfa ?? 0) as number;
  if (totalAdmins === 0 || withoutMfa === 0) return [];

  const pct = Math.round((withoutMfa * 100) / totalAdmins);
  // Severity escala con el porcentaje: si TODOS los admins estan sin
  // MFA es critico; si solo algunos es high; si <25% es medium.
  const severity = pct === 100
    ? "critical"
    : pct >= 50
    ? "high"
    : "medium";

  return [{
    check_id: "auth.mfa_admin_coverage",
    title: `${withoutMfa} of ${totalAdmins} admin(s) without MFA`,
    severity,
    impact:
      "Admins without 2FA are a single-factor compromise away from "
      + "full account takeover (password phishing / credential stuffing).",
    recommendation:
      "Ask each admin without MFA to enable it via /mfa-setup. "
      + "Consider enforcing MFA for admins at signup time as policy.",
    affected_count: withoutMfa,
    details: {
      total_admins: totalAdmins,
      with_mfa: data.with_mfa,
      without_mfa: withoutMfa,
      coverage_pct: 100 - pct,
      admins_without_mfa_ids: data.admins_without_mfa_ids,
    },
  }];
};
