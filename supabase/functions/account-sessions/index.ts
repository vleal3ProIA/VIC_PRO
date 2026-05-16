// ============================================================================
// Edge Function: account-sessions
// ----------------------------------------------------------------------------
// Listado + revocación de sesiones del propio usuario.
//
// El schema `auth` está bloqueado para acceso REST por Supabase (decisión
// de seguridad). Por eso TODA la lógica vive en RPCs SECURITY DEFINER
// del schema `public` (migration 0020):
//   - public.list_user_sessions(p_current_session_id)
//   - public.revoke_user_session(p_session_id)
//   - public.revoke_other_user_sessions(p_current_session_id)
//
// Esta función es un thin wrapper que:
//   1. valida el JWT del caller con `auth.getUser()`
//   2. extrae el `session_id` del JWT para identificar la sesión actual
//   3. invoca la RPC correspondiente
//   4. devuelve el resultado al cliente
//
// La autorización efectiva está dentro de la RPC: las queries filtran por
// `auth.uid()`, así que el caller solo ve/borra SUS propias sesiones —
// imposible tocar las de otro usuario aunque pase un session_id ajeno.
//
// Acciones: list, revoke, revoke_others. Rate limit 30/h.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";

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

/// Decodifica el claim `session_id` del JWT (sin verificar firma — ya la
/// validó `auth.getUser()`). Devuelve null si no aparece o el token está
/// malformado.
function extractSessionId(authHeader: string | null): string | null {
  if (!authHeader) return null;
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    let payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    while (payload.length % 4 !== 0) payload += "=";
    const decoded = JSON.parse(atob(payload));
    const sid = decoded?.session_id;
    return typeof sid === "string" ? sid : null;
  } catch {
    return null;
  }
}

Deno.serve(withSentry("account-sessions", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // userClient — usa el JWT del caller, hereda su `auth.uid()` dentro de
  // las RPCs SECURITY DEFINER. CRÍTICO: si usaras `admin` (service_role)
  // aquí, `auth.uid()` dentro de la RPC sería NULL y no devolvería nada.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  // Rate limit con service_role (escribe en su tabla bypassando RLS).
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `account:sessions:user:${user.id}`,
    limit: 30,
    windowSeconds: 3600,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const action = body.action as string | undefined;
  const currentSessionId = extractSessionId(authHeader);

  // ──────────────────────────────── LIST ────────────────────────────────

  if (action === "list") {
    const { data, error } = await userClient.rpc("list_user_sessions", {
      p_current_session_id: currentSessionId,
    });
    if (error) return json({ error: "db_error", detail: error.message }, 500);
    return json(
      {
        sessions: data ?? [],
        current_session_id: currentSessionId,
      },
      200,
    );
  }

  // ─────────────────────────────── REVOKE ───────────────────────────────

  if (action === "revoke") {
    const sessionId = body.session_id as string | undefined;
    if (!sessionId) return json({ error: "missing_session_id" }, 400);

    const { data, error } = await userClient.rpc("revoke_user_session", {
      p_session_id: sessionId,
    });
    if (error) return json({ error: "db_error", detail: error.message }, 500);
    if (data !== true) return json({ error: "not_found" }, 404);

    return json(
      { ok: true, was_current: sessionId === currentSessionId },
      200,
    );
  }

  // ─────────────────────────── REVOKE OTHERS ────────────────────────────

  if (action === "revoke_others") {
    if (!currentSessionId) {
      return json({ error: "no_current_session" }, 400);
    }
    const { data, error } = await userClient.rpc(
      "revoke_other_user_sessions",
      { p_current_session_id: currentSessionId },
    );
    if (error) return json({ error: "db_error", detail: error.message }, 500);
    return json({ ok: true, revoked_count: (data as number) ?? 0 }, 200);
  }

  return json({ error: "unknown_action" }, 400);
}));
