// Check: webhook endpoints activos con consecutive_failures alto. La
// app desactiva automaticamente endpoints tras N failures, pero si
// `consecutive_failures > 5` y siguen `active=true` significa que
// se acercan al umbral o ya se desactivaron y no se ha resuelto el
// origen.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const { data, error } = await admin
    .from("webhook_endpoints")
    .select(
      "id, tenant_id, user_id, url, consecutive_failures, active, "
        + "disabled_reason",
    )
    .or("consecutive_failures.gte.5,disabled_reason.eq.too_many_failures");

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "webhooks.failing_endpoints failed",
      severity: "info",
      impact: "Could not query webhook endpoints.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const failing = (data as Array<Record<string, unknown>>) ?? [];
  if (failing.length === 0) return [];

  return [{
    check_id: "webhooks.failing_endpoints",
    title: `${failing.length} webhook endpoint(s) failing or disabled`,
    severity: "medium",
    impact:
      "These webhooks are not delivering events to the user's "
      + "configured URL. If the user expects realtime notifications "
      + "(payments, signups, etc.) they are missing them.",
    recommendation:
      "Notify the affected users via /admin/users -> message. "
      + "Or have them visit /account-settings/webhooks and re-test "
      + "the endpoint themselves.",
    affected_count: failing.length,
    details: { endpoints: failing },
  }];
};
