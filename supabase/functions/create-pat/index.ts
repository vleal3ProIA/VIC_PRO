// ============================================================================
// Edge Function: create-pat
// ----------------------------------------------------------------------------
// Crea un Personal Access Token (PAT) para el user autenticado. Es el
// UNICO punto de entrada para emitir tokens -- la tabla
// `personal_access_tokens` NO permite INSERT vIa RLS porque hay que
// generar el secret + hashearlo + devolverlo una sola vez al cliente.
//
// Flujo:
//   1. Valida JWT + extrae user.id.
//   2. Lee body: { name, scopes?, expires_in_days? }.
//   3. Valida name (1..80), scopes subset de ['read', 'write'], expires
//      entero >=1 si se manda.
//   4. Rate limit 10/h/user (evita abuso si el dialog se loopea).
//   5. Genera 32 bytes random crypto-strong.
//   6. Construye raw token: `pat_<8-char-prefix>_<base64url-32-bytes>`.
//      - prefix = primeros 8 chars del base64url de los random bytes.
//      - raw = "pat_" + prefix + "_" + base64url(bytes).
//   7. Computa SHA-256 del raw -> token_hash.
//   8. INSERT en personal_access_tokens con service_role (bypassa RLS).
//   9. Devuelve { id, name, prefix, scopes, expires_at, created_at,
//      token } al cliente. `token` es el RAW y solo se devuelve aqui --
//      si el user lo pierde, debe crear otro.
//
// Body:
//   {
//     "name": "CI deploy script",
//     "scopes": ["read", "write"],     // opcional, default ['read']
//     "expires_in_days": 90             // opcional, null = no caduca
//   }
//
// Respuesta 201:
//   {
//     "id": "<uuid>",
//     "name": "CI deploy script",
//     "prefix": "pat_a1b2c3d4",
//     "scopes": ["read"],
//     "expires_at": "2026-08-15T12:34:56Z",  // o null
//     "created_at": "2026-05-17T12:34:56Z",
//     "token": "pat_a1b2c3d4_<base64url-43-chars>"   // SOLO 1 vez
//   }
//
// Seguridad: JWT obligatorio. Rate limit 10/h/user. El secret nunca
// se loguea ni vuelve a aparecer en ninguna otra respuesta.
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

const VALID_SCOPES = new Set(["read", "write"]);

// base64url sin padding -- alfabeto URL-safe ([A-Za-z0-9_-]).
function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(withSentry("create-pat", async (req) => {
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

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `create-pat:user:${user.id}`,
    limit: 10,
    windowSeconds: 3600,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  // ─────────────────────────── Validacion ───────────────────────────

  const name = (body.name as string | undefined)?.trim();
  if (!name || name.length < 1 || name.length > 80) {
    return json({ error: "invalid_name" }, 400);
  }

  let scopes: string[] = ["read"];
  if (Array.isArray(body.scopes)) {
    const raw = body.scopes as unknown[];
    const cleaned = Array.from(
      new Set(raw.filter((s): s is string => typeof s === "string")),
    );
    if (cleaned.length === 0) {
      return json({ error: "empty_scopes" }, 400);
    }
    for (const s of cleaned) {
      if (!VALID_SCOPES.has(s)) {
        return json({ error: "invalid_scope", scope: s }, 400);
      }
    }
    scopes = cleaned;
  }

  let expiresAt: string | null = null;
  if (body.expires_in_days !== undefined && body.expires_in_days !== null) {
    const days = Number(body.expires_in_days);
    if (!Number.isInteger(days) || days < 1 || days > 3650) {
      return json({ error: "invalid_expires_in_days" }, 400);
    }
    expiresAt = new Date(Date.now() + days * 86400_000).toISOString();
  }

  // ─────────────────────────── Generacion ───────────────────────────

  // 32 random bytes -> ~43 chars base64url. Resistencia practica
  // equivalente a una clave de 256 bits.
  const randomBytes = new Uint8Array(32);
  crypto.getRandomValues(randomBytes);
  const secretPart = base64UrlEncode(randomBytes);

  // Prefix visible (8 chars) extraido del secret -- es deterministico
  // a partir del propio token, asi el user puede emparejar "el token
  // que copie" con "el item de la lista" sin tener que guardar nada.
  const prefixBody = secretPart.slice(0, 8);
  const prefix = `pat_${prefixBody}`;
  const rawToken = `${prefix}_${secretPart}`;
  const tokenHash = await sha256Hex(rawToken);

  // ─────────────────────────── Insert ───────────────────────────

  const { data: row, error: insErr } = await admin
    .from("personal_access_tokens")
    .insert({
      user_id: user.id,
      name,
      prefix,
      token_hash: tokenHash,
      scopes,
      expires_at: expiresAt,
    })
    .select("id, name, prefix, scopes, expires_at, created_at")
    .single();

  if (insErr) {
    // Colision de hash (extremadamente improbable con 32 bytes) o
    // cualquier otro error -- devolvemos 500 generico, NO logueamos
    // el raw token jamas.
    return json({ error: "db_error", detail: insErr.message }, 500);
  }

  return json(
    {
      id: row.id,
      name: row.name,
      prefix: row.prefix,
      scopes: row.scopes,
      expires_at: row.expires_at,
      created_at: row.created_at,
      token: rawToken,
    },
    201,
  );
}));
