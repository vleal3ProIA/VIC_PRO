// ============================================================================
// Edge Function: admin-users
// ----------------------------------------------------------------------------
// Acciones administrativas sobre users que requieren modificar
// `auth.users` o usar `supabase.auth.admin.*` con service_role:
//
//   - `block`        : banea temporalmente al user. Body: { user_id, until_iso }
//   - `unblock`      : limpia banned_until. Body: { user_id }
//   - `deactivate`   : pone banned_until al año 2099 (perma) + revoca sessions
//                       Body: { user_id }
//   - `reactivate`   : limpia banned_until (= unblock pero distinto label en UI)
//                       Body: { user_id }
//   - `send_email`   : delega a la Edge Function `send-email` con type=broadcast.
//                       Body: { user_id, subject, body_html }
//
// **Acceso**: solo admin (JWT con rol admin en profiles).
//
// Por que Edge Function y no RPC:
//   - `auth.users.banned_until` se puede actualizar via SQL pero romper
//     triggers de Supabase Auth no esta documentado. La API oficial
//     `auth.admin.updateUserById({ ban_duration })` es la forma soportada.
//   - Revocar sessions: `auth.admin.signOut(user_id, scope='others'|'global')`
//     no tiene equivalente SQL limpio.
//   - Send email: ya tenemos la function `send-email`; aqui solo pasamos
//     params.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
import { adminClient, sendEmail } from "../_shared/email.ts";
import { fetchAppName, renderEmail } from "../_shared/email_templates.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

// Fecha "perma ban" para distinguir deactivate vs block temporal.
// Año 2099-12-31 → claramente nunca expira en condiciones normales.
const PERMA_BAN_DATE = "2099-12-31T23:59:59Z";

Deno.serve(withSentry("admin-users", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // ─────────────── Auth: admin only ───────────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  const { data: profile } = await userClient
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  if (profile?.role !== "admin") {
    return json({ error: "forbidden" }, 403);
  }

  // ─────────────── Parse body ───────────────
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const action = body.action as string | undefined;
  const targetUserId = body.user_id as string | undefined;

  if (!action) return json({ error: "missing_action" }, 400);
  if (!targetUserId) return json({ error: "missing_user_id" }, 400);

  // Auto-proteccion: nunca dejes que un admin se bloquee a si mismo
  // (se quedaria sin acceso al panel). Permitir solo si hay > 1 admin.
  if (targetUserId === user.id && action !== "send_email") {
    return json({ error: "cannot_self_modify" }, 400);
  }

  const admin = adminClient();

  // ─────────────── Acciones ───────────────
  switch (action) {
    case "block": {
      const untilIso = body.until_iso as string | undefined;
      if (!untilIso) return json({ error: "missing_until_iso" }, 400);
      const until = new Date(untilIso);
      if (isNaN(until.valueOf()) || until <= new Date()) {
        return json({ error: "invalid_until" }, 400);
      }
      // El SDK acepta `ban_duration` en formato '24h', '7d', etc., o
      // 'none'. Calculamos la duracion en horas para mayor precision.
      const hours = Math.ceil((until.valueOf() - Date.now()) / 3_600_000);
      // deno-lint-ignore no-explicit-any
      const { error } = await (admin.auth as any).admin.updateUserById(
        targetUserId,
        { ban_duration: `${hours}h` },
      );
      if (error) return json({ error: "auth_update_failed", detail: error.message }, 500);
      return json({ ok: true, until_iso: untilIso }, 200);
    }

    case "unblock":
    case "reactivate": {
      // deno-lint-ignore no-explicit-any
      const { error } = await (admin.auth as any).admin.updateUserById(
        targetUserId,
        { ban_duration: "none" },
      );
      if (error) return json({ error: "auth_update_failed", detail: error.message }, 500);
      return json({ ok: true }, 200);
    }

    case "deactivate": {
      // Perma-ban: banned_until al 2099 (la UI lo lee como 'deactivated').
      // Despues, revocamos todas las sessions activas para forzar logout.
      // ban_duration soporta formato extendido — pero para ir al año 2099
      // necesitamos calcular horas.
      const target = new Date(PERMA_BAN_DATE);
      const hours = Math.ceil((target.valueOf() - Date.now()) / 3_600_000);
      // deno-lint-ignore no-explicit-any
      const { error: banErr } = await (admin.auth as any).admin.updateUserById(
        targetUserId,
        { ban_duration: `${hours}h` },
      );
      if (banErr) return json({ error: "auth_update_failed", detail: banErr.message }, 500);
      // Revoca sessions globalmente.
      // deno-lint-ignore no-explicit-any
      await (admin.auth as any).admin.signOut(targetUserId, "global").catch(
        // signOut puede fallar silenciosamente si no hay session activa;
        // no abortamos.
        () => {},
      );
      return json({ ok: true }, 200);
    }

    case "send_email": {
      const subject = (body.subject as string | undefined)?.trim();
      const bodyHtml = (body.body_html as string | undefined)?.trim();
      if (!subject || !bodyHtml) {
        return json({ error: "missing_subject_or_body" }, 400);
      }
      if (subject.length > 200) {
        return json({ error: "subject_too_long" }, 400);
      }
      if (bodyHtml.length > 5000) {
        return json({ error: "body_too_long" }, 400);
      }

      // Lookup user email + locale.
      // deno-lint-ignore no-explicit-any
      const { data: userData, error: ueErr } = await (admin.auth as any)
        .admin.getUserById(targetUserId);
      if (ueErr || !userData?.user) {
        return json({ error: "user_not_found" }, 404);
      }
      const targetEmail = userData.user.email as string | undefined;
      if (!targetEmail) {
        return json({ error: "user_has_no_email" }, 400);
      }
      const { data: targetProfile } = await admin
        .from("profiles")
        .select("locale")
        .eq("id", targetUserId)
        .maybeSingle();
      const locale = (targetProfile?.locale as string | undefined) ?? "en";

      const appName = await fetchAppName(admin);
      const rendered = renderEmail({
        type: "broadcast",
        locale,
        appName,
        data: { subject, body: bodyHtml },
      });
      const result = await sendEmail(admin, {
        type: "broadcast",
        to: targetEmail,
        toUserId: targetUserId,
        locale,
        subject: rendered.subject,
        htmlBody: rendered.htmlBody,
        textBody: rendered.textBody,
        meta: { sent_by_admin: user.id },
      });
      return json(
        { ok: result.ok, log_id: result.logId, error: result.error },
        200,
      );
    }

    default:
      return json({ error: "unknown_action" }, 400);
  }
}));
