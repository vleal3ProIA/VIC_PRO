// ============================================================================
// Edge Function: account-sessions
// ----------------------------------------------------------------------------
// Listado + revocación de sesiones del propio usuario. NO admin —
// cualquier usuario autenticado solo puede ver/revocar SUS sesiones.
//
// Tabla origen: `auth.sessions` (schema interno de Supabase Auth). La
// usamos con service_role (bypass RLS) y filtramos por `user_id =
// auth.uid()` extraído del JWT del caller — así no necesitamos exponer
// el schema auth al cliente.
//
// Identificación de la sesión ACTUAL: el JWT de Supabase incluye el
// claim `session_id` desde GoTrue v2. Lo decodificamos del Authorization
// header (sin verificar firma — la firma ya la validó el gateway al
// llamar a /auth/v1/user; aquí solo extraemos el id como string).
//
// Acciones:
//
//   { "action": "list" }
//     Devuelve `{sessions: [{id, user_agent, ip, created_at, updated_at,
//                             not_after, aal, is_current}, ...]}`
//     ordenadas por updated_at desc.
//
//   { "action": "revoke", "session_id": "<uuid>" }
//     Borra la sesión indicada. Si es la actual, el cliente recibe ok
//     pero la próxima petición fallará por 401 — la UI navega a /login.
//
//   { "action": "revoke_others" }
//     Borra TODAS menos la actual. Si no se puede identificar la actual
//     desde el JWT, devuelve error `no_current_session`.
//
// Seguridad: JWT requerido. Rate limit 30/h/user (ratos de "limpieza"
// no son frecuentes; un atacante con JWT no gana mucho borrando sus
// propias sesiones, pero limitamos por buen gusto).
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

/// Decodifica el payload de un JWT sin verificar firma. Devuelve el
/// claim `session_id` o `null` si no está presente. Solo lo usamos para
/// extraer el id; la firma ya se validó al hacer `auth.getUser()`.
function extractSessionId(authHeader: string | null): string | null {
  if (!authHeader) return null;
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    // base64url → base64 estándar (Deno's atob necesita padding).
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

  // Validamos el JWT con el user client.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  // Rate limit.
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
    const { data, error } = await admin
      .schema("auth")
      .from("sessions")
      .select("id, user_agent, ip, created_at, updated_at, not_after, aal")
      .eq("user_id", user.id)
      .order("updated_at", { ascending: false, nullsFirst: false });
    if (error) return json({ error: "db_error", detail: error.message }, 500);

    const sessions = (data ?? []).map((row) => ({
      ...row,
      // Stringify la IP — supabase la devuelve como string ya, pero
      // dejamos explícita la forma del payload.
      ip: row.ip == null ? null : String(row.ip),
      is_current: currentSessionId != null && row.id === currentSessionId,
    }));
    return json({ sessions, current_session_id: currentSessionId }, 200);
  }

  // ─────────────────────────────── REVOKE ───────────────────────────────

  if (action === "revoke") {
    const sessionId = body.session_id as string | undefined;
    if (!sessionId) return json({ error: "missing_session_id" }, 400);

    const { error, count } = await admin
      .schema("auth")
      .from("sessions")
      .delete({ count: "exact" })
      .eq("id", sessionId)
      .eq("user_id", user.id);
    if (error) return json({ error: "db_error", detail: error.message }, 500);
    if ((count ?? 0) === 0) return json({ error: "not_found" }, 404);

    // Si revocamos la actual, también limpiamos los refresh_tokens
    // asociados para que el cliente no pueda renovar el JWT.
    await admin
      .schema("auth")
      .from("refresh_tokens")
      .update({ revoked: true })
      .eq("session_id", sessionId);

    return json({ ok: true, was_current: sessionId === currentSessionId }, 200);
  }

  // ─────────────────────────── REVOKE OTHERS ────────────────────────────

  if (action === "revoke_others") {
    if (!currentSessionId) {
      // Sin id de sesión actual no podemos garantizar que la nuestra no
      // se borre — abortamos para que el cliente no se sake a sí mismo
      // del sistema sin querer.
      return json({ error: "no_current_session" }, 400);
    }

    const { error, count } = await admin
      .schema("auth")
      .from("sessions")
      .delete({ count: "exact" })
      .eq("user_id", user.id)
      .neq("id", currentSessionId);
    if (error) return json({ error: "db_error", detail: error.message }, 500);

    // Revocar también los refresh tokens de las sesiones eliminadas.
    // Como Supabase los borra en cascade al borrar la session (FK),
    // esto es defensivo: si en alguna versión cambian el cascade, aún
    // dejamos los refresh tokens revocados.
    await admin
      .schema("auth")
      .from("refresh_tokens")
      .update({ revoked: true })
      .eq("user_id", user.id)
      .neq("session_id", currentSessionId);

    return json({ ok: true, revoked_count: count ?? 0 }, 200);
  }

  return json({ error: "unknown_action" }, 400);
}));
