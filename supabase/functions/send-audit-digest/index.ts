// ============================================================================
// Edge Function: send-audit-digest (PR 0080)
// ----------------------------------------------------------------------------
// Endpoint INTERNO invocado por el trigger SQL `fire_audit_digest_trg`
// (migracion 0080) cuando un audit AUTOMATICO (triggered_by IS NULL)
// pasa a status='completed'.
//
// Para cada recipient (super_admins + role='admin', de-duplicado por id):
//   1) Inserta una fila en `public.notifications` (in-app badge).
//   2) Envia un email via sendEmail() (template super_admin_alert).
//
// Body:
//   { audit_id: uuid }
//
// Auth:
//   - Solo header `X-Internal-Auth: <SERVICE_ROLE_KEY>`. 403 otherwise.
//   - Endpoint server-to-server, nunca expuesto al cliente.
//   - config.toml: verify_jwt = false.
//
// Responses (siempre 200 salvo error de validacion):
//   200 { ok: true,  recipients: N }
//   200 { ok: true,  recipients: 0, reason: 'no_recipients' }
//   200 { ok: false, reason: 'not_completed' }      // audit no completado
//   200 { ok: false, reason: 'not_found' }          // audit no existe
//   4xx -> error de validacion (body, auth)
//
// Idempotencia: NO se gestiona aqui. El trigger dispara una sola vez
// por transicion de status. Si el mismo audit_id se invoca dos veces
// (ej. re-trigger manual via workflow_dispatch), enviamos digest dos
// veces. Anyadimos `meta.audit_id` en email_log para que un futuro
// PR pueda de-duplicar consultando email_log.
// ============================================================================

import { withSentry } from "../_shared/sentry.ts";
import { adminClient, sendEmail } from "../_shared/email.ts";
import { fetchAppName, renderEmail } from "../_shared/email_templates.ts";
import { t } from "../_shared/i18n.ts";

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

// ─────────────── Tipos ───────────────

type Severity = "critical" | "high" | "medium" | "low" | "info";

interface AuditFinding {
  check_id: string;
  title?: string;
  severity: Severity;
  impact?: string;
  recommendation?: string;
  affected_count?: number;
  count?: number; // algunos checks legacy usan `count` en lugar de affected_count
  details?: Record<string, unknown>;
}

interface AuditReportRow {
  id: string;
  status: string;
  triggered_by: string | null;
  findings: AuditFinding[] | null;
  summary: Record<string, unknown> | null;
}

type ProfileRow = { id: string; locale: string | null };

// Orden de severidad (critical primero). Usado para ordenar el top-5.
const SEVERITY_RANK: Record<Severity, number> = {
  critical: 0,
  high: 1,
  medium: 2,
  low: 3,
  info: 4,
};

function escHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Cuenta findings por severity, defensivo ante valores raros.
function countBySeverity(
  findings: AuditFinding[],
): Record<Severity, number> {
  const result: Record<Severity, number> = {
    critical: 0,
    high: 0,
    medium: 0,
    low: 0,
    info: 0,
  };
  for (const f of findings) {
    const sev = f.severity;
    if (sev in result) {
      result[sev]++;
    }
  }
  return result;
}

// Top-5 sorted by severity asc (critical first), then count desc, then
// check_id alfabetico. Los findings sin severity conocida quedan al
// final (info).
function pickTopFindings(
  findings: AuditFinding[],
  n: number,
): AuditFinding[] {
  const copy = [...findings];
  copy.sort((a, b) => {
    const sa = SEVERITY_RANK[a.severity] ?? 99;
    const sb = SEVERITY_RANK[b.severity] ?? 99;
    if (sa !== sb) return sa - sb;
    const ca = a.affected_count ?? a.count ?? 0;
    const cb = b.affected_count ?? b.count ?? 0;
    if (ca !== cb) return cb - ca;
    return (a.check_id ?? "").localeCompare(b.check_id ?? "");
  });
  return copy.slice(0, n);
}

// Determina `notifications.type` segun la severidad mas alta presente.
function severityToNotifType(
  bySev: Record<Severity, number>,
): "info" | "warning" | "error" {
  if (bySev.critical > 0) return "error";
  if (bySev.high > 0) return "warning";
  return "info";
}

Deno.serve(withSentry("send-audit-digest", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // ─────────────── Auth: X-Internal-Auth obligatorio ───────────────
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;

  const internalAuth = req.headers.get("X-Internal-Auth");
  if (internalAuth !== serviceRoleKey) {
    return json({ error: "forbidden" }, 403);
  }

  // ─────────────── Body ───────────────
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const auditId = body.audit_id as string | undefined;
  if (!auditId) {
    return json({ error: "missing_audit_id" }, 400);
  }

  const admin = adminClient();

  // ─────────────── Read audit_reports ───────────────
  const { data: reportRow, error: reportErr } = await admin
    .from("audit_reports")
    .select("id, status, triggered_by, findings, summary")
    .eq("id", auditId)
    .maybeSingle();

  if (reportErr) {
    return json(
      { error: "audit_report_query_failed", detail: reportErr.message },
      500,
    );
  }
  if (!reportRow) {
    // No fail: el trigger pudo haber pasado un id que ya fue borrado
    // por una purga (audit > 90 dias) entre dispatch y handler.
    return json({ ok: false, reason: "not_found" }, 200);
  }

  const report = reportRow as AuditReportRow;
  if (report.status !== "completed") {
    return json({ ok: false, reason: "not_completed" }, 200);
  }

  // ─────────────── Recipients: super_admins + role='admin', dedup ───────────────
  // Una sola query: OR entre is_super_admin=true y role='admin'. El
  // de-dup natural lo hace el SELECT (cada profile aparece UNA vez).
  const { data: profilesRaw, error: pErr } = await admin
    .from("profiles")
    .select("id, locale")
    .or("is_super_admin.eq.true,role.eq.admin");

  if (pErr) {
    return json(
      { error: "recipients_query_failed", detail: pErr.message },
      500,
    );
  }

  const profiles = (profilesRaw as ProfileRow[] | null) ?? [];
  if (profiles.length === 0) {
    return json(
      { ok: true, recipients: 0, reason: "no_recipients" },
      200,
    );
  }

  // Resolver emails via auth.users. La query de profiles no trae email.
  // deno-lint-ignore no-explicit-any
  const { data: usersRaw } = await (admin.auth as any).admin.listUsers({
    perPage: 1000,
  });
  const recipientSet = new Set(profiles.map((p) => p.id));
  // deno-lint-ignore no-explicit-any
  const emailById = new Map<string, string>();
  for (const u of (usersRaw?.users ?? []) as Array<{ id: string; email?: string }>) {
    if (recipientSet.has(u.id) && u.email) {
      emailById.set(u.id, u.email);
    }
  }

  // ─────────────── App name (branding) ───────────────
  const appName = await fetchAppName(admin);

  // ─────────────── Compute summary ───────────────
  const findings = report.findings ?? [];
  const bySeverity = countBySeverity(findings);
  const total = findings.length;
  const top5 = pickTopFindings(findings, 5);
  const notifType = severityToNotifType(bySeverity);

  const actionUrl = `/admin/audit/${report.id}`;
  // URL absoluta para el boton CTA del email (links internos no son
  // clicables en clientes de correo).
  const fullActionUrl = `${supabaseUrl}${actionUrl}`;

  // Params i18n compartidos por todos los recipients.
  const baseParams: Record<string, string> = {
    count: String(total),
    critical: String(bySeverity.critical),
    high: String(bySeverity.high),
    medium: String(bySeverity.medium),
    low: String(bySeverity.low),
    info: String(bySeverity.info),
    app_name: appName,
  };

  // ─────────────── Per-recipient processing ───────────────
  const CONCURRENCY = 25;

  async function processOne(p: ProfileRow): Promise<boolean> {
    const email = emailById.get(p.id);
    if (!email) {
      console.warn(`[send-audit-digest] recipient ${p.id} has no email`);
      return false;
    }
    const locale = p.locale ?? "en";

    const title = t(locale, "audit_digest.title", baseParams);
    const bodyText = total === 0
      ? t(locale, "audit_digest.no_issues", baseParams)
      : t(locale, "audit_digest.body", baseParams);
    const subjectStr = t(locale, "audit_digest.subject", baseParams);
    const greeting = t(locale, "audit_digest.greeting", baseParams);
    const intro = t(locale, "audit_digest.intro", baseParams);
    const reportLinkLabel = t(locale, "audit_digest.report_link", baseParams);
    const topFindingsLabel = t(locale, "audit_digest.top_findings", baseParams);

    // ── 1) In-app notification ──
    const { error: notifErr } = await admin
      .from("notifications")
      .insert({
        user_id: p.id,
        tenant_id: null,
        type: notifType,
        category: "audit.digest",
        title,
        body: bodyText,
        action_url: actionUrl,
      });
    if (notifErr) {
      console.warn(
        `[send-audit-digest] notif insert failed for ${p.id}:`,
        notifErr.message,
      );
    }

    // ── 2) Email body HTML ──
    // Patron MINIMO -- mismo formato que `notify-super-admins` (que si
    // llega a Gmail sin filtrarse). HTML rico (tablas, botones con
    // background-color, badges con <code>) hace que Gmail descarte
    // silenciosamente los digests aunque el SMTP devuelva 250 OK.
    //
    // El detalle visual rico lo ve el admin EN la pagina
    // /admin/audit/<id> -- el email es solo un trigger para abrirla.
    const lines: string[] = [
      `<p>${escHtml(greeting)}</p>`,
      `<p>${escHtml(intro)}</p>`,
    ];
    if (total === 0) {
      lines.push(`<p>${escHtml(t(locale, "audit_digest.no_issues", baseParams))}</p>`);
    } else {
      // Breakdown en texto plano dentro de <p>. Mas ligero que tabla.
      lines.push(
        `<p>${escHtml(t(locale, "audit_digest.body", baseParams))}</p>`,
      );
      if (top5.length > 0) {
        const topLine = top5.map((f) => {
          const label = (f.title && f.title.trim().length > 0)
            ? f.title
            : f.check_id;
          return `${f.severity}: ${label}`;
        }).join("; ");
        lines.push(
          `<p><strong>${escHtml(topFindingsLabel)}:</strong> ${
            escHtml(topLine)
          }</p>`,
        );
      }
    }
    lines.push(
      `<p style="margin-top:16px;"><a href="${
        escHtml(fullActionUrl)
      }" style="color:#2563EB;">${escHtml(reportLinkLabel)}</a></p>`,
    );
    const bodyHtmlAlert = lines.join("\n");

    try {
      const rendered = renderEmail({
        type: "audit_digest",
        locale,
        appName,
        data: {
          subject: subjectStr,
          body_html: bodyHtmlAlert,
        },
      });
      const result = await sendEmail(admin, {
        type: "audit_digest",
        to: email,
        toUserId: p.id,
        locale,
        subject: rendered.subject,
        htmlBody: rendered.htmlBody,
        textBody: rendered.textBody,
        meta: {
          // Marca para una futura de-duplicacion via email_log.
          audit_id: report.id,
          total,
          critical: bySeverity.critical,
          high: bySeverity.high,
        },
      });
      if (!result.ok) {
        console.warn(
          `[send-audit-digest] email failed for ${p.id}:`,
          result.error,
        );
      }
    } catch (e) {
      console.warn(
        `[send-audit-digest] email exception for ${p.id}:`,
        e instanceof Error ? e.message : String(e),
      );
    }
    return true;
  }

  let processed = 0;
  for (let i = 0; i < profiles.length; i += CONCURRENCY) {
    const chunk = profiles.slice(i, i + CONCURRENCY);
    const results = await Promise.all(chunk.map(processOne));
    for (const ok of results) {
      if (ok) processed++;
    }
  }

  return json({ ok: true, recipients: processed }, 200);
}));
