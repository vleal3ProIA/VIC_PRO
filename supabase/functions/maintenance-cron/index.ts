// ============================================================================
// Edge Function: maintenance-cron
// ----------------------------------------------------------------------------
// Endpoint llamado por un cron externo (GitHub Actions tipicamente)
// para ejecutar tareas de mantenimiento periodicas que en PR-Audit-4 y
// PR cron-purges-extended se documentaron como "TODO config manual":
//
//   - recover_stuck:  marca como 'failed' los audits que llevan
//                      status='running' > 30 min.
//   - daily_purges:   purga registros antiguos en 4 tablas (audit_reports,
//                      audit_logs, email_log, notifications) con los
//                      defaults conservadores.
//   - run_audit:      lanza un audit completo del sistema (proxy a la EF
//                      `run-audit` con X-Internal-Auth).
//
// **Por que NO usamos las RPCs `admin_*_purge_old`**: esas RPCs validan
// `is_admin()` con `auth.uid()`, y el cron no tiene user context.
// Aqui ejecutamos los DELETE/UPDATE directamente con service_role
// (bypassa RLS) -- los mismos defaults, los mismos floors de
// seguridad replicados.
//
// **Auth**: validacion via header `X-Cron-Secret` matchear `CRON_SECRET`
// env var. Es shared secret entre GitHub Actions y este endpoint. NO
// usamos JWT porque GitHub Actions no tiene sesion de Supabase.
//
// **Rate limit**: 60 invocaciones/hora desde la misma "IP" (ya que el
// secret podria filtrarse). Es generoso para uso legitimo y suficiente
// para frenar abuso.
//
// **config.toml**: verify_jwt = false (necesario, GitHub Actions no
// manda JWT).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

// Whitelist de tasks. Si quieres anyadir una, anyadela aqui Y maneja
// el case del switch mas abajo.
const VALID_TASKS = new Set<string>([
  "recover_stuck",
  "daily_purges",
  "run_audit",
]);

// Defaults coherentes con los floors de las RPCs `admin_*_purge_old`
// (migraciones 0041 y 0042).
const STUCK_AUDIT_MIN_AGE_MIN = 30;       // audits 'running' mas viejos
const PURGE_AUDIT_REPORTS_DAYS = 90;       // PR-Audit-4
const PURGE_AUDIT_LOGS_DAYS = 90;          // PR cron-purges-extended
const PURGE_EMAIL_LOG_DAYS = 180;          // idem
const PURGE_NOTIFICATIONS_DAYS = 60;       // idem (solo leidas)

Deno.serve(withSentry("maintenance-cron", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // ─── Auth: shared secret ───
  const provided = req.headers.get("X-Cron-Secret");
  const expected = Deno.env.get("CRON_SECRET");
  if (!expected) {
    // Sin secret configurado, NO aceptar requests -- preferimos hard-fail
    // a un endpoint inseguro.
    return json({ error: "cron_secret_not_configured" }, 500);
  }
  if (!provided || provided !== expected) {
    return json({ error: "forbidden" }, 403);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  // ─── Rate limit ───
  // El bucket key es generico ('global') porque el cron no tiene un
  // "user". Limit 60/h cubre con holgura los schedules (cada 30min =
  // 48/dia) y frena loops accidentales.
  const rateOk = await checkRateLimit(admin, {
    bucketKey: "maintenance-cron:global",
    limit: 60,
    windowSeconds: 3600,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // ─── Parse body ───
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const task = body.task as string | undefined;
  if (!task) return json({ error: "missing_task" }, 400);
  if (!VALID_TASKS.has(task)) {
    return json({ error: "unknown_task", task }, 400);
  }

  // ─── Dispatch ───
  switch (task) {
    case "recover_stuck":
      return await _recoverStuck(admin);
    case "daily_purges":
      return await _dailyPurges(admin);
    case "run_audit":
      return await _runAudit(supabaseUrl, serviceRoleKey);
    default:
      return json({ error: "unknown_task" }, 400);
  }
}));

// ─────────────────────── Tasks ───────────────────────

// deno-lint-ignore no-explicit-any
async function _recoverStuck(admin: any): Promise<Response> {
  const cutoffMs = Date.now() - STUCK_AUDIT_MIN_AGE_MIN * 60 * 1000;
  const cutoffIso = new Date(cutoffMs).toISOString();

  // Bypasseamos la RPC `admin_audit_recover_stuck()` (que valida is_admin())
  // y ejecutamos el UPDATE con service_role. La logica es identica a la
  // RPC -- mantenerlas alineadas si cambia el mensaje de error.
  const { data, error } = await admin
    .from("audit_reports")
    .update({
      status: "failed",
      error:
        "stuck_recovered: audit was running > 30 min and was marked " +
        "failed by maintenance-cron. The Edge Function probably died " +
        "mid-run (deploy, OOM, timeout). No data loss -- just rerun.",
      finished_at: new Date().toISOString(),
    })
    .eq("status", "running")
    .lt("started_at", cutoffIso)
    .select("id");

  if (error) {
    return json({ error: "db_error", detail: error.message }, 500);
  }
  return json({ ok: true, task: "recover_stuck", recovered: data?.length ?? 0 }, 200);
}

// deno-lint-ignore no-explicit-any
async function _dailyPurges(admin: any): Promise<Response> {
  const results: Record<string, number | string> = {};

  // Purga 1: audit_reports > 90 dias.
  results.audit_reports = await _purgeOlderThan(
    admin,
    "audit_reports",
    "started_at",
    PURGE_AUDIT_REPORTS_DAYS,
  );

  // Purga 2: audit_logs > 90 dias.
  results.audit_logs = await _purgeOlderThan(
    admin,
    "audit_logs",
    "occurred_at",
    PURGE_AUDIT_LOGS_DAYS,
  );

  // Purga 3: email_log > 180 dias.
  results.email_log = await _purgeOlderThan(
    admin,
    "email_log",
    "created_at",
    PURGE_EMAIL_LOG_DAYS,
  );

  // Purga 4: notifications > 60 dias Y leidas (read_at IS NOT NULL).
  // Es la unica con un filtro adicional -- las no leidas se respetan.
  const notifCutoff = new Date(
    Date.now() - PURGE_NOTIFICATIONS_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();
  const { data, error } = await admin
    .from("notifications")
    .delete()
    .lt("created_at", notifCutoff)
    .not("read_at", "is", null)
    .select("id");
  if (error) {
    results.notifications = `error: ${error.message}`;
  } else {
    results.notifications = data?.length ?? 0;
  }

  return json({ ok: true, task: "daily_purges", ...results }, 200);
}

async function _runAudit(
  supabaseUrl: string,
  serviceRoleKey: string,
): Promise<Response> {
  // Invocamos la EF `run-audit` con X-Internal-Auth (patron documentado
  // en run-audit/index.ts). Esto crea un audit con triggered_by=null
  // (sin user humano) que aparece en /admin/audit.
  try {
    const res = await fetch(`${supabaseUrl}/functions/v1/run-audit`, {
      method: "POST",
      headers: {
        "X-Internal-Auth": serviceRoleKey,
        "Content-Type": "application/json",
      },
    });
    const payload = await res.json();
    if (!res.ok) {
      return json(
        { error: "run_audit_failed", detail: payload, status: res.status },
        500,
      );
    }
    return json({ ok: true, task: "run_audit", ...payload }, 200);
  } catch (e) {
    return json(
      {
        error: "run_audit_exception",
        detail: e instanceof Error ? e.message : String(e),
      },
      500,
    );
  }
}

/**
 * Helper para purgar rows > N dias en una tabla. Devuelve el conteo
 * de rows borradas o un string con el error.
 */
// deno-lint-ignore no-explicit-any
async function _purgeOlderThan(
  admin: any,
  table: string,
  timestampColumn: string,
  days: number,
): Promise<number | string> {
  const cutoff = new Date(
    Date.now() - days * 24 * 60 * 60 * 1000,
  ).toISOString();
  const { data, error } = await admin
    .from(table)
    .delete()
    .lt(timestampColumn, cutoff)
    .select("id");
  if (error) return `error: ${error.message}`;
  return data?.length ?? 0;
}
