// ============================================================================
// Edge Function: run-audit (Audit Center V1 -- PR-Audit-2: 12 checks reales)
// ----------------------------------------------------------------------------
// Ejecuta los 12 checks de Audit Center que detectan problemas en el
// estado del sistema (RLS, secrets, datos huerfanos, configuracion).
// Solo admin puede invocarla.
//
// **Arquitectura**:
//   - Cada check vive en `_checks/<id>.ts` con interfaz `AuditCheckRunner`.
//   - El runner los ejecuta secuencialmente con try/catch individual --
//     si uno falla, el resto sigue.
//   - Acumula findings en `audit_reports.findings` jsonb.
//   - Resumen agregado en `audit_reports.summary` (counts por severity).
//
// **Flow**:
//   1. Auth admin (JWT o X-Internal-Auth con service_role).
//   2. Rate limit 1/min/user.
//   3. INSERT row 'running' -> devuelve report_id inmediato.
//   4. Procesa los 12 checks en background con EdgeRuntime.waitUntil.
//   5. UPDATE row con findings + summary + status='completed'.
//
// **PR-Audit-3** anyadira UI en /admin/audit.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { captureError, captureMessage, withSentry } from "../_shared/sentry.ts";
import { checkCapability } from "../_shared/capability.ts";

import type { AuditFinding, AuditCheckRunner } from "./_checks/_types.ts";

// ─────────────── Imports de los 12 checks ───────────────
// Cada modulo exporta `runCheck` que cumple `AuditCheckRunner`.
import { runCheck as rlsCoverage } from "./_checks/rls_coverage.ts";
import { runCheck as rlsNoPolicies } from "./_checks/rls_no_policies.ts";
import { runCheck as mfaAdminCoverage } from "./_checks/mfa_admin_coverage.ts";
import { runCheck as orphanPendingUploads } from "./_checks/orphan_pending_uploads.ts";
import { runCheck as virusScanErrors } from "./_checks/virus_scan_errors.ts";
import { runCheck as suspiciousUploadsRecent } from "./_checks/suspicious_uploads_recent.ts";
import { runCheck as stuckBroadcasts } from "./_checks/stuck_broadcasts.ts";
import { runCheck as emailFailureRate } from "./_checks/email_failure_rate.ts";
import { runCheck as failingWebhooks } from "./_checks/failing_webhooks.ts";
import { runCheck as unusedPats } from "./_checks/unused_pats.ts";
import { runCheck as broadcastsEmptyAudience } from "./_checks/broadcasts_empty_audience.ts";
import { runCheck as legacyPendingUploads } from "./_checks/legacy_pending_uploads.ts";
import { runCheck as orphanTenants } from "./_checks/orphan_tenants.ts";

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

type AuditSeverity = "critical" | "high" | "medium" | "low" | "info";

/// Lista ordenada de checks que se ejecutan. Para anyadir uno nuevo:
/// 1) Crear `_checks/<nuevo>.ts` con `export const runCheck: AuditCheckRunner`.
/// 2) Importarlo arriba.
/// 3) Anyadirlo a este array.
const CHECKS: Array<{ id: string; run: AuditCheckRunner }> = [
  { id: "rls.coverage", run: rlsCoverage },
  { id: "rls.no_policies", run: rlsNoPolicies },
  { id: "auth.mfa_admin_coverage", run: mfaAdminCoverage },
  { id: "uploads.orphan_pending", run: orphanPendingUploads },
  { id: "uploads.scan_errors", run: virusScanErrors },
  { id: "uploads.suspicious_recent", run: suspiciousUploadsRecent },
  { id: "uploads.legacy_no_magic", run: legacyPendingUploads },
  { id: "broadcasts.stuck_sending", run: stuckBroadcasts },
  { id: "broadcasts.empty_audience", run: broadcastsEmptyAudience },
  { id: "emails.failure_rate", run: emailFailureRate },
  { id: "webhooks.failing_endpoints", run: failingWebhooks },
  { id: "tokens.unused_long_lived", run: unusedPats },
  { id: "tenants.orphan", run: orphanTenants },
];

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

  // ─── Auth ───
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
    const { data: profile } = await userClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();
    if (profile?.role !== "admin") {
      return json({ error: "forbidden" }, 403);
    }
    // PR-Super-A3: capability gate (super pasa siempre). Solo en la
    // rama de user real -- la rama isInternal (cron de mantenimiento)
    // no pasa por aqui y no requiere capability.
    const capErr = await checkCapability(userClient, user.id, "run_audits");
    if (capErr) return json({ error: capErr }, 403);
    triggeredBy = user.id;
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // ─── Rate limit ───
  const rateKey = triggeredBy ?? `internal:${serviceRoleKey.slice(0, 8)}`;
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `run-audit:${rateKey}`,
    limit: 1,
    windowSeconds: 60,
  });
  if (!rateOk) {
    return json({ error: "rate_limited" }, 429);
  }

  // ─── INSERT row 'running' ───
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

  // ─── Procesamiento en background ───
  // deno-lint-ignore no-explicit-any
  const waitUntil = (globalThis as any).EdgeRuntime?.waitUntil?.bind(
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime,
  );

  if (typeof waitUntil === "function") {
    waitUntil(_runChecks(admin, reportId));
    return json({ ok: true, report_id: reportId, queued: true }, 200);
  } else {
    await _runChecks(admin, reportId);
    return json({ ok: true, report_id: reportId, queued: false }, 200);
  }
}));

// ─────────────────────────────────────────────────────────────────────
// Ejecuta los 12 checks secuencialmente con try/catch individual.
// Acumula findings + summary + UPDATE row.
// ─────────────────────────────────────────────────────────────────────
async function _runChecks(
  // deno-lint-ignore no-explicit-any
  admin: any,
  reportId: string,
): Promise<void> {
  const startedAt = Date.now();
  const findings: AuditFinding[] = [];

  for (const check of CHECKS) {
    try {
      const checkFindings = await check.run(admin);
      findings.push(...checkFindings);
    } catch (e) {
      // Crash de un check NO aborta el report -- lo registramos como
      // finding "audit.check_failed" y seguimos. Asi vemos en la UI
      // que el check fallo, sin perder el resto.
      const message = e instanceof Error ? e.message : String(e);
      findings.push({
        check_id: "audit.check_failed",
        title: `Check '${check.id}' crashed`,
        severity: "info",
        impact:
          `The check did not run to completion. Other findings may `
          + `be missing from this report.`,
        recommendation:
          `Investigate Sentry / Edge Function logs for stack trace.`,
        affected_count: 0,
        details: { failed_check: check.id, error: message },
      });
      await captureError(
        e instanceof Error ? e : new Error(message),
        { fn: "run-audit", stage: "check", check_id: check.id },
      );
    }
  }

  // ─── Summary agregado ───
  const bySeverity = _countBySeverity(findings);
  const summary = {
    by_severity: bySeverity,
    total_checks_run: CHECKS.length,
    total_findings: findings.length,
    duration_ms: Date.now() - startedAt,
    version: "v1",
  };

  try {
    await admin
      .from("audit_reports")
      .update({
        findings,
        summary,
        status: "completed",
        finished_at: new Date().toISOString(),
      })
      .eq("id", reportId);

    // Sentry alert si hay criticals/highs. Asi el admin recibe la
    // notificacion sin tener que pasar por /admin/audit. NO bloquea
    // -- si Sentry falla (no DSN, network), el update ya esta hecho
    // y el report es accesible.
    await _maybeSentryAlert(reportId, findings, bySeverity);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await captureError(
      e instanceof Error ? e : new Error(message),
      { fn: "run-audit", stage: "update_completed", report_id: reportId },
    );
    // Best-effort: marcar failed.
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

// ─────────────────────────────────────────────────────────────────────
// Sentry alert si hay findings critical/high.
// ----------------------------------------------------------------------
// La idea: en un proyecto con Sentry configurado, los admins reciben
// el "issue" via email/Slack inmediatamente sin tener que pasar por
// /admin/audit. Para criticals usamos level='error' (top severity en
// Sentry, dispara notificaciones), para highs 'warning' (visible pero
// menos ruidoso).
//
// **Que enviamos**: ids cortos de findings + titulos. NO mandamos
// `details` -- esos pueden contener uuids de users / paths internos
// que no queremos en logs de tercero. El admin verá el detalle en
// /admin/audit/:id.
// ─────────────────────────────────────────────────────────────────────
async function _maybeSentryAlert(
  reportId: string,
  findings: AuditFinding[],
  bySeverity: Record<AuditSeverity, number>,
): Promise<void> {
  const critical = bySeverity.critical ?? 0;
  const high = bySeverity.high ?? 0;
  if (critical === 0 && high === 0) {
    return; // nada de que alertar
  }

  try {
    const criticalFindings = findings
      .filter((f) => f.severity === "critical")
      .map((f) => `${f.check_id}: ${f.title}`);
    const highFindings = findings
      .filter((f) => f.severity === "high")
      .map((f) => `${f.check_id}: ${f.title}`);

    const level: "error" | "warning" = critical > 0 ? "error" : "warning";
    const summary = critical > 0
      ? `Audit Center: ${critical} critical finding(s)`
      : `Audit Center: ${high} high finding(s)`;

    await captureMessage(summary, level, {
      report_id: reportId,
      total_critical: critical,
      total_high: high,
      critical_findings: criticalFindings,
      high_findings: highFindings,
    });
  } catch (e) {
    // No queremos que el alerting bloquee la response. Solo log.
    console.error("[run-audit] sentry alert failed:", e);
  }
}
