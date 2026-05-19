// Check: broadcasts completados o en curso con recipients_total = 0.
// Suele indicar filtros mal configurados (target_value mal apuntado,
// target_type='plan' con slug inexistente). El admin penso que
// estaba mandando algo a 100 users y en realidad fueron 0.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const { data, error } = await admin
    .from("broadcasts")
    .select("id, subject, target_type, target_value, status, created_at")
    .in("status", ["sending", "sent"])
    .eq("recipients_total", 0)
    .order("created_at", { ascending: false })
    .limit(20);

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "broadcasts.empty_audience failed",
      severity: "info",
      impact: "Could not query broadcasts with 0 recipients.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const empty = (data as Array<Record<string, unknown>>) ?? [];
  if (empty.length === 0) return [];

  return [{
    check_id: "broadcasts.empty_audience",
    title: `${empty.length} broadcast(s) sent to 0 recipients`,
    severity: "medium",
    impact:
      "These broadcasts had their target filter return zero matches. "
      + "The admin thought they were communicating with users but "
      + "nothing was delivered.",
    recommendation:
      "Review the `target_type` + `target_value` of each. Common "
      + "bugs: slug del plan typeado mal, codigo de locale invalido, "
      + "status='active' cuando no hay users activos en ese filtro.",
    affected_count: empty.length,
    details: { broadcasts: empty },
  }];
};
