// ============================================================================
// Edge Function: verify-password (PR-F)
// ----------------------------------------------------------------------------
// Verifica la contrasena del user autenticado y registra una
// "verificacion fresca" en `auth_recent_verifications`. Las Edge
// Functions destructivas (delete-account, create-pat con scope write,
// etc.) consultan esa tabla antes de actuar.
//
// **Body**:
//   {
//     "password": "...",
//     "action_kind": "delete_account" | "create_pat_write" | ...
//   }
//
// **Respuesta exitosa** (200):
//   { "ok": true, "expires_at": "<ISO timestamp>" }
//
// **Errores**:
//   - 400 missing_fields
//   - 400 invalid_action_kind
//   - 401 invalid_token
//   - 401 invalid_password
//   - 429 rate_limited
//
// **Como funciona la verificacion**:
//   Supabase no expone un endpoint "validar password sin iniciar
//   sesion". Workaround estandar: creamos un cliente temporal con
//   anon key y llamamos a signInWithPassword. Si retorna sesion, el
//   password es correcto. Inmediatamente cerramos esa sesion temporal
//   (no contamina al user, solo deja un evento `user.signed_in` en el
//   audit log de Supabase Auth -- aceptable).
//
// **Rate limit**: 10 intentos por hora por user (mismo que login). Mas
// alto seria abuso facil; mas bajo molestaria a users despistados.
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

// Whitelist de action_kinds aceptados. Mantenemos sincronizado con
// SECURITY.md sec.10.3 y los chequeos en las Edge Functions
// destructivas. Si quieres anyadir una accion nueva, anyadela aqui y
// haz un chequeo `has_recent_verification('nuevo_kind')` en su
// Edge Function correspondiente.
const VALID_ACTION_KINDS = new Set<string>([
  "delete_account",
  "create_pat_write",
  // Futuro (anyadir cuando se implementen los endpoints):
  // 'change_email',
  // 'webhook_secret_rotate',
  // 'role_change',
]);

// TTL de la verificacion: 5 min. Coherente con la migracion 0037 y
// con el default de has_recent_verification RPC.
const TTL_MS = 5 * 60 * 1000;

Deno.serve(withSentry("verify-password", async (req) => {
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

  // 1) Identificar al user via JWT.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user || !user.email) {
    return json({ error: "invalid_token" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // 2) Rate limit. Si el atacante tiene el JWT pero NO el password,
  //    podria intentar fuerza bruta a traves de este endpoint. Lo
  //    capamos a 10/h/user. Por debajo del de login (5/15min) porque
  //    aqui ya ha pasado un primer login -- es factor adicional.
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `verify-password:user:${user.id}`,
    limit: 10,
    windowSeconds: 3600,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // 3) Parsear body.
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const password = body.password as string | undefined;
  const actionKind = body.action_kind as string | undefined;
  if (!password || !actionKind) {
    return json({ error: "missing_fields" }, 400);
  }
  if (!VALID_ACTION_KINDS.has(actionKind)) {
    return json({ error: "invalid_action_kind" }, 400);
  }

  // 4) Verificar password con cliente temporal. NO usamos el userClient
  //    actual porque eso rotaria su JWT y forzaria al frontend a
  //    recargar sesion. Cliente temporal -> sesion descartable.
  const tempClient = createClient(supabaseUrl, anonKey);
  const { data: signInData, error: signInErr } =
    await tempClient.auth.signInWithPassword({
      email: user.email,
      password,
    });
  if (signInErr || !signInData.session) {
    // No queremos distinguir "user no existe" de "password mal" --
    // siempre devolvemos invalid_password. El user ya esta autenticado
    // con su JWT, asi que sabemos que existe; aqui solo verificamos
    // password. Si signIn falla, password mal.
    return json({ error: "invalid_password" }, 401);
  }

  // Sanity check: el user del signIn debe ser el mismo del JWT. Si no
  // matchea, el password es de otra cuenta con mismo email (no deberia
  // pasar, pero defensiva).
  if (signInData.user?.id !== user.id) {
    await tempClient.auth.signOut();
    return json({ error: "user_mismatch" }, 401);
  }

  // 5) Cerrar la sesion temporal. NO afecta al JWT del user en el
  //    cliente real -- ese sigue valido.
  try {
    await tempClient.auth.signOut();
  } catch (_) {
    // signOut puede fallar si la sesion ya expiro o por red. No
    // bloqueamos la verificacion por esto.
  }

  // 6) Registrar la verificacion con service_role.
  const { error: insErr } = await admin
    .from("auth_recent_verifications")
    .insert({
      user_id: user.id,
      action_kind: actionKind,
    });
  if (insErr) {
    return json({ error: "db_error", detail: insErr.message }, 500);
  }

  const expiresAt = new Date(Date.now() + TTL_MS).toISOString();
  return json({ ok: true, expires_at: expiresAt }, 200);
}));
