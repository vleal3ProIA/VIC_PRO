// ============================================================================
// Edge Function: send-email
// ----------------------------------------------------------------------------
// Endpoint generico para enviar emails desde cualquier parte del
// sistema: stripe-webhook, broadcasts del admin, test pings de la UI
// admin, etc. Centralizado en una sola funcion para que TODO email
// pase por el mismo helper (logging + SMTP) y para que migrar de
// proveedor (SMTP -> Resend etc.) sea cambiar un solo archivo.
//
// **Acceso**:
//   - Header `X-Internal-Auth: <SUPABASE_SERVICE_ROLE_KEY>` -> permitido.
//   - Header `Authorization: Bearer <jwt>` con rol admin -> permitido
//     (para que la UI admin pueda mandar test pings sin exponer el
//     service_role al cliente).
//   - Cualquier otro caso -> 403.
//
// **Body**:
//   {
//     "type":      "signup" | "recovery" | "magic_link" | "change_email"
//                | "invite" | "plan_changed" | "broadcast" | "test",
//     "to":        "user@example.com",
//     "to_user_id": "<uuid>"   // opcional
//     "locale":    "es"         // opcional, default 'en'
//     "data": {                 // claves segun el tipo
//       "action_url": "https://...",
//       "plan_name": "Pro",
//       ...
//     }
//   }
//
// **Respuesta**:
//   200 -> { ok: true, log_id }
//   200 -> { ok: false, log_id, error } (smtp fallo pero logueamos)
//   4xx -> error de validacion
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
import {
  adminClient,
  EmailType,
  sendEmail,
  SendEmailParams,
} from "../_shared/email.ts";
import { fetchAppName, renderEmail } from "../_shared/email_templates.ts";

const VALID_TYPES: EmailType[] = [
  "signup",
  "recovery",
  "magic_link",
  "change_email",
  "invite",
  "plan_changed",
  "broadcast",
  "test",
];

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

Deno.serve(withSentry("send-email", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  // ─────────────── Authorization ───────────────
  // 1) Internal: header X-Internal-Auth con el service role key.
  const internalAuth = req.headers.get("X-Internal-Auth");
  const isInternal = internalAuth === serviceRoleKey;

  // 2) Admin: JWT del cliente + rol admin.
  let isAdmin = false;
  if (!isInternal) {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "forbidden" }, 403);
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "forbidden" }, 403);

    const { data: profile } = await userClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();
    isAdmin = profile?.role === "admin";
    if (!isAdmin) return json({ error: "forbidden" }, 403);
  }

  // ─────────────── Body ───────────────
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const type = body.type as EmailType | undefined;
  const to = body.to as string | undefined;
  const toUserId = (body.to_user_id as string | undefined) ?? null;
  const locale = (body.locale as string | undefined) ?? "en";
  const data = (body.data as Record<string, string> | undefined) ?? {};

  if (!type || !VALID_TYPES.includes(type)) {
    return json({ error: "invalid_type" }, 400);
  }
  if (!to || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(to)) {
    return json({ error: "invalid_to" }, 400);
  }

  // ─────────────── Render + send ───────────────
  const admin = adminClient();
  const appName = await fetchAppName(admin);
  const rendered = renderEmail({ type, locale, appName, data });

  const sendParams: SendEmailParams = {
    type,
    to,
    toUserId,
    locale,
    subject: rendered.subject,
    htmlBody: rendered.htmlBody,
    textBody: rendered.textBody,
    meta: { data, via: isInternal ? "internal" : "admin" },
  };

  const result = await sendEmail(admin, sendParams);
  return json(
    {
      ok: result.ok,
      log_id: result.logId,
      error: result.error,
    },
    200,
  );
}));
