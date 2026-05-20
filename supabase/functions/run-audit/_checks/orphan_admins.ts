// Check: admins (role='admin', NO super) con CERO capabilities concedidas.
//
// Severity: medium. Estos accounts pueden autenticarse en la zona admin
// pero -- tras el modelo de capabilities (migracion 0044, PR-Super-A) --
// no pueden ejecutar NINGUNA accion admin (ni ver paginas, ni llamar
// EFs gateadas, ni escribir en tablas con RLS por capability). Es una
// cuenta admin "muerta": superficie de ataque innecesaria. Si sus
// credenciales se filtran, el atacante gana un punto de apoyo dentro
// de la zona admin sin coste. Principio de minimo privilegio (OWASP
// A01) + minimizar superficie (defensa en profundidad).
//
// El super admin se excluye SIEMPRE (tiene todas las caps implicitas).

import type { AuditCheckRunner } from "./_types.ts";

export const runCheck: AuditCheckRunner = async (admin) => {
  // 1) Admins normales (role='admin'); separamos al super por su flag.
  const { data: adminsData, error: e1 } = await admin
    .from("profiles")
    .select("id, is_super_admin")
    .eq("role", "admin");

  if (e1) {
    return [{
      check_id: "audit.check_failed",
      title: "access.orphan_admins failed",
      severity: "info",
      impact: "Could not enumerate admins.",
      recommendation: "Check Supabase logs / migration 0044.",
      affected_count: 0,
      details: { error: e1.message },
    }];
  }

  const admins = (adminsData as Array<{ id: string; is_super_admin: boolean }>) ??
    [];
  const normalAdmins = admins.filter((a) => a.is_super_admin !== true);
  if (normalAdmins.length === 0) return [];

  // 2) Capabilities concedidas a esos admins.
  const ids = normalAdmins.map((a) => a.id);
  const { data: capsData, error: e2 } = await admin
    .from("admin_capabilities")
    .select("user_id")
    .in("user_id", ids);

  if (e2) {
    return [{
      check_id: "audit.check_failed",
      title: "access.orphan_admins failed",
      severity: "info",
      impact: "Could not enumerate admin capabilities.",
      recommendation: "Check Supabase logs / migration 0044.",
      affected_count: 0,
      details: { error: e2.message },
    }];
  }

  const caps = (capsData as Array<{ user_id: string }>) ?? [];
  const withCaps = new Set(caps.map((c) => c.user_id));
  const orphans = normalAdmins.filter((a) => !withCaps.has(a.id));

  if (orphans.length === 0) return [];

  return [{
    check_id: "access.orphan_admins",
    title:
      `${orphans.length} admin(s) with role='admin' but zero capabilities`,
    severity: "medium",
    impact:
      "These accounts can authenticate into the admin area but have no "
      + "capabilities granted, so they cannot perform any admin action. "
      + "A dead admin account is unnecessary attack surface: if its "
      + "credentials are compromised, the attacker gains an admin-zone "
      + "foothold for free.",
    recommendation:
      "Review each in /admin/admins: either grant the capabilities they "
      + "actually need, or revoke the admin role entirely. Never leave "
      + "role='admin' with no capabilities.",
    affected_count: orphans.length,
    details: { user_ids: orphans.map((a) => a.id) },
  }];
};
