// ============================================================================
// Edge Function: run-audit (Audit Center V1 -- PR-Audit-1: esqueleto)
// ----------------------------------------------------------------------------
// Ejecuta una auditoria del estado del sistema en runtime. Solo admin
// puede invocarla. Cada ejecucion crea una fila en `audit_reports` con
// los findings detectados (RLS, secrets, datos huerfanos, etc.).
//
// **Flow**:
//   1. Auth: admin via JWT del header Authorization. Rechaza si no.
//   2. Rate limit: max 1 audit/min por user (los checks pesan en BD).
//   3. INSERT en audit_reports con status='running', triggered_by=admin.id.
//   4. Registra los checks en EdgeRuntime.waitUntil para que sigan
//      corriendo despues de responder al cliente. Devuelve report_id
//      inmediato -- el cliente pollea o invalida el provider tras unos
//      segundos.
//   5. Cada check ejecuta su query, devuelve findings, se acumulan.
//   6. UPDATE audit_reports con findings + summary + status='completed'.
//
// **PR-Audit-1 (esqueleto)**: solo paso 1-3 + un placeholder de check.
// Los 12 checks reales llegan en PR-Audit-2.
//
// **Header de auth interno**: tambien acepta X-Internal-Auth con
// service_role (igual que scan-upload) para invocaciones programaticas
// futuras (cron, scheduled audits).
//
// **verify_jwt=false** en config.toml: la authenticidad se verifica
// dentro de la function (admin via JWT decoded o service_role).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { captureError, withSentry } from "../_shared/sentry.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-internal-auth",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

/// Severidades soportadas. Sincronizado con
/// `lib/features/audit_center/domain/audit_severity.dart` (PR-Audit-3).
type AuditSeverity = "critical" | "high" | "medium" | "low" | "info";

interface AuditFinding {
  check_id: string;
  title: string;
  severity: AuditSeverity;
  impact: string;
  recommendation: string;
  affected_count: number;
  details?: Record<string, unknown>;
}

Deno.serve(withSentry("run-audit", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // ─────────────── Auth: admin via JWT o service_role ───────────────
  const internalAuth = req.headers.get("X-Internal-Auth");
  const isInternal = internalAuth === serviceRoleKey;

  let triggeredBy: string | null = null;

  if (!isInternal) {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "missing_authorization" }, 401);
    }
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) {
      return json({ error: "invalid_token" }, 401);
    }
    // Verificar rol admin via profiles. is_admin() es SECURITY DEFINER.
    const { data: profile } = await userClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();
    if (profile?.role !== "admin") {
      return json({ error: "forbidden" }, 403);
    }
    triggeredBy = user.id;
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // ─────────────── Rate limit ───────────────
  // 1 audit / 60s por admin. Razon: cada audit hace ~12 queries pesadas
  // (pg_policies, count(*) sobre uploads/broadcasts/etc.). Permitir
  // spam degradaria la BD.
  const rateKey = triggeredBy ?? `internal:${serviceRoleKey.slice(0, 8)}`;
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `run-audit:${rateKey}`,
    limit: 1,
    windowSeconds: 60,
  });
  if (!rateOk) {
    return json({ error: "rate_limited" }, 429);
  }

  // ─────────────── INSERT row 'running' ───────────────
  const { data: row, error: insErr } = await admin
    .from("audit_reports")
    .insert({
      triggered_by: triggeredBy,
      status: "running",
    })
    .select("id")
    .single();
  if (insErr || !row) {
    return json(
      { error: "db_error", detail: insErr?.message },
      500,
    );
  }
  const reportId = row.id as string;

  // ─────────────── Procesamiento en background ───────────────
  // PR-Audit-1: solo un check placeholder. En PR-Audit-2 vienen los 12
  // checks reales.
  //
  // Pattern: registramos la promesa con EdgeRuntime.waitUntil para que
  // el runtime espere a que termine ANTES de cerrar el worker. Asi
  // podemos responder 200 al cliente inmediato sin perder la audit.

  // deno-lint-ignore no-explicit-any
  const waitUntil = (globalThis as any).EdgeRuntime?.waitUntil?.bind(
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime,
  );

  if (typeof waitUntil === "function") {
    waitUntil(_runChecks(admin, reportId));
    return json({ ok: true, report_id: reportId, queued: true }, 200);
  } else {
    // Fallback sincrono: para entornos sin waitUntil (test local).
    await _runChecks(admin, reportId);
    return json({ ok: true, report_id: reportId, queued: false }, 200);
  }
}));

// ─────────────────────────────────────────────────────────────────────
// Ejecuta los checks y actualiza el row. PR-Audit-1: placeholder. Los
// checks reales se anyaden en PR-Audit-2 -- cada uno como funcion
// async que recibe `admin` y devuelve `AuditFinding[]`.
// ─────────────────────────────────────────────────────────────────────
async function _runChecks(
  // deno-lint-ignore no-explicit-any
  admin: any,
  reportId: string,
): Promise<void> {
  const startedAt = Date.now();
  const findings: AuditFinding[] = [];
  let checksRun = 0;

  try {
    // ─── Placeholder check: audit infra OK ───
    // Comprueba que la propia tabla audit_reports existe (sanity test).
    // En PR-Audit-2 esto se reemplaza por los 12 checks reales.
    checksRun++;
    const { error: sanityErr } = await admin
      .from("audit_reports")
      .select("id")
      .eq("id", reportId)
      .maybeSingle();

    if (sanityErr) {
      findings.push({
        check_id: "audit.infrastructure",
        title: "Audit infrastructure unreachable",
        severity: "critical",
        impact: "The audit system itself cannot query its own tables.",
        recommendation:
          "Check Supabase service health and audit_reports RLS policies.",
        affected_count: 1,
        details: { error: sanityErr.message },
      });
    }

    // ─── Resumen ───
    const duration = Date.now() - startedAt;
    const summary = {
      by_severity: _countBySeverity(findings),
      total_checks_run: checksRun,
      total_findings: findings.length,
      duration_ms: duration,
      version: "v1-skeleton",
    };

    await admin
      .from("audit_reports")
      .update({
        findings,
        summary,
        status: "completed",
        finished_at: new Date().toISOString(),
      })
      .eq("id", reportId);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await captureError(
      e instanceof Error ? e : new Error(message),
      { fn: "run-audit", stage: "_runChecks", report_id: reportId },
    );
    await admin
      .from("audit_reports")
      .update({
        status: "failed",
        error: message.slice(0, 500),
        finished_at: new Date().toISOString(),
      })
      .eq("id", reportId);
  }
}

/// Agrupa findings por severidad. Util para summary y para la UI.
function _countBySeverity(
  findings: AuditFinding[],
): Record<AuditSeverity, number> {
  const result: Record<AuditSeverity, number> = {
    critical: 0,
    high: 0,
    medium: 0,
    low: 0,
    info: 0,
  };
  for (const f of findings) {
    result[f.severity]++;
  }
  return result;
}
