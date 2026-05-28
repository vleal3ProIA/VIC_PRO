// Check: tables with RLS enabled but no policies defined.
//
// Resultado: tabla bloqueada total para roles `authenticated` y
// `anon`. Puede ser intencional (ej. audit log append-only que solo
// se toca via service_role), pero suele indicar policies olvidadas.
//
import type { AuditFinding, AuditCheckRunner } from "./_types.ts";

// Allowlist intencional: estas tablas son SOLO-servidor a proposito --
// las gestiona el `service_role` desde Edge Functions y un cliente nunca
// debe tocarlas. Tener RLS activado y SIN policies es el comportamiento
// correcto y seguro (anyadirles una policy de cliente seria un agujero,
// sobre todo en `webhook_secrets`). Por eso las excluimos del finding
// para no generar ruido (falso positivo conocido). Si aparece CUALQUIER
// otra tabla con RLS y sin policies, si se reporta.
const INTENTIONAL_SERVICE_ROLE_ONLY = new Set<string>([
  "webhook_secrets", // secretos de firma de webhooks -- jamas al cliente
  "webauthn_challenges", // retos efimeros de passkeys, server-side
  "edge_rate_limits", // contadores de rate-limit, server-side
  // IA (Fase 0): API keys cifradas de proveedores. SOLO las leen las EFs
  // que llaman al modelo (`ai-gateway`); cliente NUNCA debe acceder.
  "ai_credentials",
  // Biblioteca compartida (shared_library, Fase 2+): pool global de
  // índices/views/cuestionarios reutilizables. La escritura va por la EF
  // `validate-index` y la lectura por `generate-index`. El cliente nunca
  // toca estas tablas directamente.
  "shared_indexes",
  "shared_contributions",
]);

export const runCheck: AuditCheckRunner = async (admin) => {
  const { data, error } = await admin.rpc(
    "admin_audit_tables_no_policies",
  );

  if (error) {
    return [{
      check_id: "audit.check_failed",
      title: "rls.no_policies failed",
      severity: "info",
      impact: "Could not enumerate tables with RLS but no policies.",
      recommendation: "Check migration 0040.",
      affected_count: 0,
      details: { error: error.message },
    }];
  }

  const allTables = (data as Array<{ table_name: string }>) ?? [];
  // Excluimos las tablas solo-servidor intencionales (allowlist arriba).
  const tables = allTables.filter(
    (t) => !INTENTIONAL_SERVICE_ROLE_ONLY.has(t.table_name),
  );
  if (tables.length === 0) return [];

  return [{
    check_id: "rls.no_policies",
    title: "Tables with RLS but no policies",
    severity: "medium",
    impact:
      "These tables are effectively inaccessible to regular users. "
      + "If this is unintentional, the feature using them is broken.",
    recommendation:
      "Review each table. If access from clients is expected, add "
      + "appropriate `create policy` statements. If write-only by "
      + "service_role (audit logs, etc.), this is fine -- document it.",
    affected_count: tables.length,
    details: { tables: tables.map((t) => t.table_name) },
  }];
};
