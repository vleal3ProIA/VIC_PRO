// Check: tenants sin miembros. Cada user tiene un tenant personal
// creado en signup; si todos sus miembros se fueron (o no hay
// tenant_members nunca), el tenant queda huerfano. Suele ser bug del
// flow de invites o de delete-account.

import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  // Query: tenant_id que no tenga ninguna fila en tenant_members.
  // Lo hacemos con un RPC inline via raw SQL no es directo en
  // PostgREST; en su lugar, traemos todos los tenants y todos los
  // members, y restamos en JS. Para escala pequena/mediana funciona
  // bien.
  const tenantsRes = await admin
    .from("tenants")
    .select("id, name, slug, owner_id, created_at, is_personal");

  if (tenantsRes.error) {
    return [{
      check_id: "audit.check_failed",
      title: "tenants.orphan failed",
      severity: "info",
      impact: "Could not query tenants.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: tenantsRes.error.message },
    }];
  }

  const tenants = (tenantsRes.data as Array<{
    id: string;
    name: string;
    slug: string;
    owner_id: string;
    created_at: string;
    is_personal: boolean;
  }>) ?? [];

  if (tenants.length === 0) return [];

  const membersRes = await admin
    .from("tenant_members")
    .select("tenant_id");

  if (membersRes.error) {
    return [{
      check_id: "audit.check_failed",
      title: "tenants.orphan members fetch failed",
      severity: "info",
      impact: "Could not query tenant_members.",
      recommendation: "Check Supabase logs.",
      affected_count: 0,
      details: { error: membersRes.error.message },
    }];
  }

  const membersByTenant = new Set<string>();
  for (const m of (membersRes.data ?? []) as Array<{ tenant_id: string }>) {
    membersByTenant.add(m.tenant_id);
  }

  const orphans = tenants.filter((t) => !membersByTenant.has(t.id));
  if (orphans.length === 0) return [];

  return [{
    check_id: "tenants.orphan",
    title: `${orphans.length} tenant(s) without any members`,
    severity: "low",
    impact:
      "Tenants with zero members are unreachable. They consume row "
      + "space and confuse admin reporting (total tenants count).",
    recommendation:
      "Review each. Likely safe to delete: "
      + "`delete from tenants where id in (...);` (cascades to "
      + "tenant_subscriptions). Investigate root cause if many "
      + "appear (broken invite flow? race in delete-account?).",
    affected_count: orphans.length,
    details: {
      tenants: orphans.map((t) => ({
        id: t.id,
        name: t.name,
        slug: t.slug,
        is_personal: t.is_personal,
        created_at: t.created_at,
      })),
    },
  }];
};
