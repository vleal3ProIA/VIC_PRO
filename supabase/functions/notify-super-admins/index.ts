// ============================================================================
// Edge Function: notify-super-admins
// ----------------------------------------------------------------------------
// Endpoint INTERNO que recibe un evento de ciclo de vida de usuario
// (registered / role_changed / deleted) y dispara:
//
//   1) Una fila en `public.notifications` por cada super_admin (in-app).
//   2) Un email transaccional via send-email a cada super_admin.
//
// Quien lo llama:
//   - Migration 0074:
//       · trigger AFTER INSERT en profiles -> user.registered
//       · RPCs super_admin_promote_to_admin / super_admin_revoke_admin
//         -> user.role_changed
//   - EF delete-account -> user.deleted (BEFORE de borrar el row).
//
// Auth:
//   - Solo via header `X-Internal-Auth: <SERVICE_ROLE_KEY>`. Sin esto
//     -> 403. Es endpoint server-to-server, NUNCA expuesto al cliente.
//   - config.toml: verify_jwt = false (el pg_net.http_post desde un
//     trigger SQL no manda JWT; valida el X-Internal-Auth).
//
// Body:
//   {
//     event:     'user.registered' | 'user.role_changed' | 'user.deleted',
//     user_id:   string                // sujeto del evento
//     email:     string                // email del sujeto (display)
//     username:  string                // username del sujeto (display)
//     prev_role?: string               // solo en role_changed
//     new_role?:  string               // solo en role_changed
//   }
//
// Respuesta:
//   200 -> { ok: true, recipients: N }
//   200 -> { ok: true, recipients: 0, reason: 'no_super_admins' }
//   4xx -> error de validacion
// ============================================================================

import { withSentry } from "../_shared/sentry.ts";
import { adminClient, sendEmail } from "../_shared/email.ts";
import { fetchAppName, renderEmail } from "../_shared/email_templates.ts";
import { t } from "../_shared/i18n.ts";

const VALID_EVENTS = new Set<string>([
  "user.registered",
  "user.role_changed",
  "user.deleted",
]);

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

// Map evento -> categoria que persistimos en notifications.category.
// La UI de /notifications agrupa por category libremente -- mantener
// estos strings estables para no romper filtros futuros.
const CATEGORY_BY_EVENT: Record<string, string> = {
  "user.registered": "user.registered",
  "user.role_changed": "user.role_changed",
  "user.deleted": "user.deleted",
};

// Map evento -> claves i18n para titulo y body de la notif in-app.
const I18N_KEY_BY_EVENT: Record<string, { title: string; body: string }> = {
  "user.registered": {
    title: "super_admin_alert.user_registered.title",
    body: "super_admin_alert.user_registered.body",
  },
  "user.role_changed": {
    title: "super_admin_alert.user_role_changed.title",
    body: "super_admin_alert.user_role_changed.body",
  },
  "user.deleted": {
    title: "super_admin_alert.user_deleted.title",
    body: "super_admin_alert.user_deleted.body",
  },
};

Deno.serve(withSentry("notify-super-admins", async (req) => {
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
    // NUNCA leakear el motivo exacto -- 403 generico.
    return json({ error: "forbidden" }, 403);
  }

  // ─────────────── Body ───────────────
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const event = body.event as string | undefined;
  const subjectUserId = body.user_id as string | undefined;
  const subjectEmail = (body.email as string | undefined) ?? "";
  const subjectUsername = (body.username as string | undefined) ?? "";
  const prevRole = (body.prev_role as string | undefined) ?? "";
  const newRole = (body.new_role as string | undefined) ?? "";

  if (!event || !VALID_EVENTS.has(event)) {
    return json({ error: "invalid_event" }, 400);
  }
  if (!subjectUserId) {
    return json({ error: "missing_user_id" }, 400);
  }
  // role_changed REQUIERE prev_role + new_role.
  if (event === "user.role_changed" && (!prevRole || !newRole)) {
    return json({ error: "missing_role_fields" }, 400);
  }

  const admin = adminClient();

  // ─────────────── Recipients: super_admins activos ───────────────
  // profiles NO tiene deleted_at (verificado contra migraciones 0001 +
  // posteriores -- solo tenants/tenant_members lo tienen). Filtramos
  // solo por is_super_admin = true.
  const { data: superAdmins, error: saErr } = await admin
    .from("profiles")
    .select("id, locale")
    .eq("is_super_admin", true);

  if (saErr) {
    return json(
      { error: "super_admins_query_failed", detail: saErr.message },
      500,
    );
  }

  type SuperRow = { id: string; locale: string | null };
  const supers = (superAdmins as SuperRow[] | null) ?? [];
  if (supers.length === 0) {
    return json({ ok: true, recipients: 0, reason: "no_super_admins" }, 200);
  }

  // Resolver emails de super_admins via auth.users (profiles no guarda
  // email; viene de auth.users).
  // deno-lint-ignore no-explicit-any
  const { data: superUsersRaw } = await (admin.auth as any).admin
    .listUsers({ perPage: 1000 });
  // Filtrar a solo los UUIDs que son super.
  const superSet = new Set(supers.map((s) => s.id));
  // deno-lint-ignore no-explicit-any
  const superUsers: Array<{ id: string; email: string }> =
    ((superUsersRaw?.users ?? []) as any[])
      .filter((u) => superSet.has(u.id) && u.email)
      .map((u) => ({ id: u.id, email: u.email as string }));

  // Mapa rapido: id -> locale
  const localeById = new Map<string, string>(
    supers.map((s) => [s.id, s.locale ?? "en"]),
  );

  // ─────────────── Counters ───────────────
  const { count: totalUsersCount } = await admin
    .from("profiles")
    .select("id", { count: "exact", head: true });
  const totalUsers = totalUsersCount ?? 0;

  // Para role_changed, calcular breakdown por role.
  const rolesBreakdown: Record<string, number> = {};
  if (event === "user.role_changed") {
    const { data: roleRows } = await admin
      .from("profiles")
      .select("role");
    const rows = (roleRows as Array<{ role: string | null }> | null) ?? [];
    for (const r of rows) {
      const k = r.role ?? "user";
      rolesBreakdown[k] = (rolesBreakdown[k] ?? 0) + 1;
    }
  }

  // Formato legible del breakdown para email/notif: "admin: 2, user: 41".
  function formatBreakdown(b: Record<string, number>): string {
    const keys = Object.keys(b).sort();
    return keys.map((k) => `${k}: ${b[k]}`).join(", ");
  }

  // ─────────────── App name (para email subject + body) ───────────────
  const appName = await fetchAppName(admin);

  // ─────────────── Deep link a la pagina de detalle del user ───────────────
  // Para event=user.deleted el user ya no existira, pero el link no
  // hace daño y mantiene consistencia. El admin puede usarlo para
  // buscar logs/auditoria.
  const actionUrl = `/admin/users/${subjectUserId}`;

  // ─────────────── Loop de recipients ───────────────
  // Si hay 10+ super_admins, en teoria deberiamos paralelizar; en la
  // practica 1-3 super es lo normal. Procesamos en paralelo con
  // cap defensivo de 25 simultaneos -- imposible llegar al limite
  // SMTP del proveedor.
  const CONCURRENCY = 25;
  const i18nKeys = I18N_KEY_BY_EVENT[event];

  async function processOne(s: SuperRow): Promise<boolean> {
    const adminEmail = superUsers.find((u) => u.id === s.id)?.email;
    if (!adminEmail) {
      // Super sin email en auth.users -> raro pero seguir.
      console.warn(`[notify-super-admins] super ${s.id} has no email`);
      return false;
    }
    const locale = localeById.get(s.id) ?? "en";

    const params: Record<string, string> = {
      username: subjectUsername || "(unknown)",
      email: subjectEmail || "(unknown)",
      total_users: String(totalUsers),
      prev_role: prevRole,
      new_role: newRole,
      roles_breakdown: formatBreakdown(rolesBreakdown),
    };

    const title = t(locale, i18nKeys.title, params);
    const bodyText = t(locale, i18nKeys.body, params);

    // 1) Insert in-app notification. type debe ser uno de los enum
    //    permitidos por 0021 (info|success|warning|error). 'info'
    //    encaja: los eventos no son errores ni warnings sino info
    //    operacional. category lleva el evento concreto para que la
    //    UI pueda filtrar/iconizar en el futuro.
    const { error: notifErr } = await admin
      .from("notifications")
      .insert({
        user_id: s.id,
        tenant_id: null,
        type: "info",
        category: CATEGORY_BY_EVENT[event],
        title,
        body: bodyText,
        action_url: actionUrl,
      });
    if (notifErr) {
      // No abortamos: si la fila falla, al menos intentamos el email.
      console.warn(
        `[notify-super-admins] notif insert failed for ${s.id}:`,
        notifErr.message,
      );
    }

    // 2) Email via renderEmail + sendEmail. El template
    //    'super_admin_alert' (registrado en email_templates.ts) usa
    //    {{subject}} y {{body_html}} del data, mismo patron que
    //    broadcast. Asi el render queda i18n-aware (footer/preheader
    //    por locale) y el contenido principal viene de _shared/i18n.ts.
    //
    // body_html: simple paragraph + datos clave. Escapamos el username
    // y email basicos para evitar inyeccion HTML.
    function escHtml(s: string): string {
      return s
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
    }
    const safeBody = escHtml(bodyText);
    const bodyHtmlAlert =
      `<p>${safeBody}</p>` +
      `<p style="margin-top:16px;"><a href="${supabaseUrl}${
        escHtml(actionUrl)
      }" style="color:#2563EB;">${escHtml(actionUrl)}</a></p>`;
    try {
      const rendered = renderEmail({
        type: "super_admin_alert",
        locale,
        appName,
        data: {
          subject: title,
          body_html: bodyHtmlAlert,
        },
      });
      const result = await sendEmail(admin, {
        type: "super_admin_alert",
        to: adminEmail,
        toUserId: s.id,
        locale,
        subject: rendered.subject,
        htmlBody: rendered.htmlBody,
        textBody: rendered.textBody,
        meta: {
          event,
          subject_user_id: subjectUserId,
        },
      });
      if (!result.ok) {
        console.warn(
          `[notify-super-admins] email failed for ${s.id}:`,
          result.error,
        );
      }
    } catch (e) {
      console.warn(
        `[notify-super-admins] email exception for ${s.id}:`,
        e instanceof Error ? e.message : String(e),
      );
    }
    return true;
  }

  let processed = 0;
  for (let i = 0; i < supers.length; i += CONCURRENCY) {
    const chunk = supers.slice(i, i + CONCURRENCY);
    const results = await Promise.all(chunk.map(processOne));
    for (const ok of results) {
      if (ok) processed++;
    }
  }

  return json({ ok: true, recipients: processed }, 200);
}));
