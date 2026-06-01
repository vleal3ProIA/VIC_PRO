// ============================================================================
// Edge Function: notify-error-report (PR 0083)
// ----------------------------------------------------------------------------
// Endpoint INTERNO invocado por el trigger SQL `fire_error_report_notify_trg`
// (migracion 0083) AFTER INSERT en `error_reports`.
//
// Para cada recipient (super_admins + admins con capability
// `view_error_reports`, de-duplicado por id):
//   1) Inserta una fila en `public.notifications` (in-app badge).
//        category = 'error.new'
//        type     = derivado de severity:
//                   - critical -> 'error'
//                   - high     -> 'warning'
//                   - else     -> 'info'
//        action_url = '/admin/errors/<id>'
//   2) Envia un email via sendEmail() (template `error_report`).
//
// Body:
//   { error_report_id: uuid }
//
// Auth:
//   - Solo header `X-Internal-Auth: <SERVICE_ROLE_KEY>`. 403 otherwise.
//   - Endpoint server-to-server, nunca expuesto al cliente.
//   - config.toml: verify_jwt = false.
//
// Responses:
//   200 { ok: true,  recipients: N }
//   200 { ok: true,  recipients: 0, reason: 'no_recipients' }
//   200 { ok: false, reason: 'not_found' }    // error_report borrado
//   4xx -> error de validacion (body, auth)
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

type Severity = "critical" | "high" | "medium" | "low";

interface ErrorReportRow {
  id: string;
  fn: string;
  error_message: string;
  severity: Severity;
}

type ProfileRow = {
  id: string;
  locale: string | null;
  display_name: string | null;
  username: string | null;
};

function severityToNotifType(s: Severity): "info" | "warning" | "error" {
  if (s === "critical") return "error";
  if (s === "high") return "warning";
  return "info";
}

function escHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

Deno.serve(withSentry("notify-error-report", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // ─────────────── Auth: X-Internal-Auth obligatorio ───────────────
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
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
  const errorReportId = body.error_report_id as string | undefined;
  if (!errorReportId) {
    return json({ error: "missing_error_report_id" }, 400);
  }

  const admin = adminClient();

  // ─────────────── Read error_reports row ───────────────
  const { data: reportRow, error: reportErr } = await admin
    .from("error_reports")
    .select("id, fn, error_message, severity")
    .eq("id", errorReportId)
    .maybeSingle();

  if (reportErr) {
    return json(
      { error: "error_report_query_failed", detail: reportErr.message },
      500,
    );
  }
  if (!reportRow) {
    // Trigger pudo haber pasado un id ya borrado (purga manual / race).
    return json({ ok: false, reason: "not_found" }, 200);
  }
  const report = reportRow as ErrorReportRow;

  // ─────────────── Recipients: super + admins con view_error_reports ───
  // 1) super_admins (siempre).
  // 2) admins con la capability `view_error_reports`.
  // De-duplicamos por id (un super que ademas tenga la capability sigue
  // contando una vez).
  const recipientIds = new Set<string>();

  const { data: superRows, error: sErr } = await admin
    .from("profiles")
    .select("id")
    .eq("is_super_admin", true);
  if (sErr) {
    return json(
      { error: "recipients_super_query_failed", detail: sErr.message },
      500,
    );
  }
  for (const r of (superRows as Array<{ id: string }> | null) ?? []) {
    recipientIds.add(r.id);
  }

  const { data: capRows, error: cErr } = await admin
    .from("admin_capabilities")
    .select("user_id")
    .eq("capability", "view_error_reports");
  if (cErr) {
    return json(
      { error: "recipients_cap_query_failed", detail: cErr.message },
      500,
    );
  }
  for (const r of (capRows as Array<{ user_id: string }> | null) ?? []) {
    recipientIds.add(r.user_id);
  }

  if (recipientIds.size === 0) {
    return json({ ok: true, recipients: 0, reason: "no_recipients" }, 200);
  }

  // Lee profiles (locale + nombre) de cada recipient.
  const { data: profilesRaw, error: pErr } = await admin
    .from("profiles")
    .select("id, locale, display_name, username")
    .in("id", Array.from(recipientIds));
  if (pErr) {
    return json(
      { error: "profiles_query_failed", detail: pErr.message },
      500,
    );
  }
  const profiles = (profilesRaw as ProfileRow[] | null) ?? [];

  // Resolver emails via auth.users (profiles no trae email).
  // deno-lint-ignore no-explicit-any
  const { data: usersRaw } = await (admin.auth as any).admin.listUsers({
    perPage: 1000,
  });
  const emailById = new Map<string, string>();
  for (const u of (usersRaw?.users ?? []) as Array<{ id: string; email?: string }>) {
    if (recipientIds.has(u.id) && u.email) {
      emailById.set(u.id, u.email);
    }
  }

  const appName = await fetchAppName(admin);
  const notifType = severityToNotifType(report.severity);
  const actionUrl = `/admin/errors/${report.id}`;
  const siteUrl = (Deno.env.get("SITE_URL")
    ?? Deno.env.get("PUBLIC_SITE_URL")
    ?? "").replace(/\/$/, "");
  const fullActionUrl = siteUrl ? `${siteUrl}${actionUrl}` : actionUrl;

  const baseParams: Record<string, string> = {
    app_name: appName,
    fn: report.fn,
    severity: report.severity,
    message: report.error_message.slice(0, 240),
  };

  // ─────────────── Per-recipient processing ───────────────
  const CONCURRENCY = 25;

  async function processOne(p: ProfileRow): Promise<boolean> {
    const email = emailById.get(p.id);
    const locale = p.locale ?? "en";

    const name = (p.display_name && p.display_name.trim())
      || (p.username && p.username.trim())
      || (email ? email.split("@")[0] : "admin");

    const title = t(locale, "error_report.title", baseParams);
    const bodyText = t(locale, "error_report.body", baseParams);
    const subjectStr = t(locale, "error_report.subject", baseParams);
    const introText = t(locale, "error_report.intro", baseParams);

    // ── 1) In-app notification (siempre, aunque el user no tenga email) ──
    const { error: notifErr } = await admin
      .from("notifications")
      .insert({
        user_id: p.id,
        tenant_id: null,
        type: notifType,
        category: "error.new",
        title,
        body: bodyText,
        action_url: actionUrl,
      });
    if (notifErr) {
      console.warn(
        `[notify-error-report] notif insert failed for ${p.id}:`,
        notifErr.message,
      );
    }

    if (!email) {
      console.warn(`[notify-error-report] recipient ${p.id} has no email`);
      return true; // in-app notif si se hizo
    }

    // ── 2) Email body HTML ──
    const bodyParts: string[] = [];
    bodyParts.push(`<p>${escHtml(introText)}</p>`);
    bodyParts.push(
      `<p><strong>${escHtml(report.fn)}</strong> &mdash; ` +
      `<em>${escHtml(report.severity)}</em></p>`,
    );
    bodyParts.push(`<p>${escHtml(report.error_message.slice(0, 480))}</p>`);
    const bodyHtmlAlert = bodyParts.join("");

    try {
      const rendered = renderEmail({
        type: "error_report",
        locale,
        appName,
        data: {
          name,
          subject: subjectStr,
          body_html: bodyHtmlAlert,
          cta_url: fullActionUrl,
        },
      });
      const result = await sendEmail(admin, {
        type: "error_report",
        to: email,
        toUserId: p.id,
        locale,
        subject: rendered.subject,
        htmlBody: rendered.htmlBody,
        textBody: rendered.textBody,
        meta: {
          error_report_id: report.id,
          severity: report.severity,
          fn: report.fn,
        },
      });
      if (!result.ok) {
        console.warn(
          `[notify-error-report] email failed for ${p.id}:`,
          result.error,
        );
      }
    } catch (e) {
      console.warn(
        `[notify-error-report] email exception for ${p.id}:`,
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
