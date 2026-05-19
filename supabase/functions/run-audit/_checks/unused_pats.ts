// Check: Personal Access Tokens activos (no revoked, no expired) que
// no se han usado nunca o que no se usan desde > 90 dias. Probablemente
// el user los olvido. Tokens dormidos = riesgo si se filtran (ej. en
// un repo publico) sin que el user lo note.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  const cutoff =
    new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
  const nowIso = new Date().toISOString();

  // Query: activos (no revoked) + no expirados + last_used null o
  // anterior al cutoff.
  const { data, error } = await admin
    .from("personal_access_tokens")
    .select("id, user_id, name, prefix, last_used_at, created_at")
    .is("revoked_at", null)
    .or(`expires_at.is.null,expires_at.gt.${nowIso}`)
    .or(`last_used_at.is.null,last_used_at.lt.${cutoff}`);

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "tokens.unused_long_lived failed",
      severity: "info",
      impact: "Could not query unused PATs.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  // Filtramos en JS: solo los que ademas son antiguos (created > 7
  // dias) -- recien creados que no se han usado son normales.
  const oneWeekAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const tokens = (data as Array<{
    id: string;
    user_id: string;
    name: string;
    prefix: string;
    last_used_at: string | null;
    created_at: string;
  }>) ?? [];
  const stale = tokens.filter((t) => {
    const createdMs = Date.parse(t.created_at);
    return createdMs < oneWeekAgo;
  });

  if (stale.length === 0) return [];

  return [{
    check_id: "tokens.unused_long_lived",
    title: `${stale.length} PAT(s) unused for over 90 days`,
    severity: "low",
    impact:
      "Dormant tokens are credential-theft risk: if leaked (e.g. "
      + "committed to a public repo), the owner won't notice because "
      + "they don't use the token themselves.",
    recommendation:
      "Notify each affected user: 'You have an old PAT that hasn't "
      + "been used in 3 months. Revoke it if you don't need it.' "
      + "Future: send automated email reminder + auto-revoke after "
      + "180 days of inactivity.",
    affected_count: stale.length,
    details: {
      tokens: stale.map((t) => ({
        id: t.id,
        user_id: t.user_id,
        name: t.name,
        prefix: t.prefix,
        last_used_at: t.last_used_at,
        created_at: t.created_at,
      })),
    },
  }];
};
