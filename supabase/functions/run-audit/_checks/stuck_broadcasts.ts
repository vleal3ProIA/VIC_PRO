// Check: broadcasts atascados en status='sending' por mas de 1h. La
// Edge Function `broadcast-dispatch` auto-invoca `continue` para
// retomar tras timeout de 5 min del worker. Si una invocacion
// `continue` falla por red, el broadcast queda colgado indefinidamente
// y los emails nunca llegan.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();

  const { data, error } = await admin
    .from("broadcasts")
    .select("id, subject, started_at, recipients_total, processed_offset")
    .eq("status", "sending")
    .lt("started_at", cutoff);

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "broadcasts.stuck_sending failed",
      severity: "info",
      impact: "Could not query stuck broadcasts.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const stuck = (data as Array<Record<string, unknown>>) ?? [];
  if (stuck.length === 0) return [];

  return [{
    check_id: "broadcasts.stuck_sending",
    title: `${stuck.length} broadcast(s) stuck in 'sending' for > 1h`,
    severity: "high",
    impact:
      "Recipients are NOT receiving these broadcasts. The dispatch "
      + "loop never resumed (likely a self-invoke `continue` failed "
      + "due to network).",
    recommendation:
      "Manually re-invoke `broadcast-dispatch` with "
      + "`{ action: 'continue', broadcast_id: <id> }` and "
      + "X-Internal-Auth header for each stuck broadcast. "
      + "Investigate Sentry for the original failure.",
    affected_count: stuck.length,
    details: { broadcasts: stuck },
  }];
};
