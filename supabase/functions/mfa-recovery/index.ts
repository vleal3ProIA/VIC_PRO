// ============================================================================
// Edge Function: mfa-recovery
// ----------------------------------------------------------------------------
// Gestiona los códigos de recuperación de MFA. Dos acciones:
//
//   { "action": "generate" }
//     - Requiere que el usuario esté a AAL2 (acaba de pasar MFA). Si se
//       permitiese a AAL1, alguien con solo la contraseña podría generarse
//       códigos y saltarse el segundo factor → AAL2 es OBLIGATORIO aquí.
//     - Genera 10 códigos, guarda solo su hash (SHA-256), borra los antiguos.
//     - Devuelve los 10 códigos en claro UNA sola vez.
//
//   { "action": "verify", "code": "xxxxx-xxxxx" }
//     - Vale a AAL1 (es el punto: recuperar acceso cuando perdiste el 2FA).
//     - Si el código es válido y no usado: lo marca usado y ELIMINA los
//       factores TOTP del usuario (con la admin API). Así deja de requerirse
//       AAL2 y el usuario entra. Debe volver a configurar MFA después.
//
// Seguridad: `verify_jwt` activo → solo se invoca con un JWT válido. Cada
// usuario opera SOLO sobre sus propios códigos y factores.
//
// Desplegar:  supabase functions deploy mfa-recovery
// (ver supabase/MFA_RECOVERY_SETUP.md)
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Alfabeto sin caracteres ambiguos (0/O, 1/l/I).
const ALPHABET = "23456789abcdefghjkmnpqrstuvwxyz";
const CODE_COUNT = 10;
const GROUP_LEN = 5; // formato: xxxxx-xxxxx

function generateCode(): string {
  const bytes = new Uint8Array(GROUP_LEN * 2);
  crypto.getRandomValues(bytes);
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    if (i === GROUP_LEN) out += "-";
    out += ALPHABET[bytes[i] % ALPHABET.length];
  }
  return out;
}

// Normaliza para comparar: minúsculas, sin espacios ni guiones.
function normalize(code: string): string {
  return code.toLowerCase().replace(/[\s-]/g, "");
}

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Decodifica el payload del JWT (sin verificar firma: `getUser` ya valida el
// token; esto solo es para leer el claim `aal`).
function jwtAal(token: string): string | null {
  try {
    const payload = token.split(".")[1];
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const decoded = JSON.parse(atob(normalized));
    return decoded.aal ?? null;
  } catch (_) {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "missing_authorization" }, 401);
    }
    const token = authHeader.replace(/^Bearer\s+/i, "");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // 1) Identificar al usuario por su token.
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userErr,
    } = await userClient.auth.getUser();
    if (userErr || !user) {
      return json({ error: "invalid_token" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const action = body?.action;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    // ---- GENERATE ----------------------------------------------------------
    if (action === "generate") {
      // AAL2 obligatorio: sin esto sería un bypass del segundo factor.
      if (jwtAal(token) !== "aal2") {
        return json({ error: "aal2_required" }, 403);
      }
      // Rate limit: 5/hora por usuario. Operación rara (solo al activar
      // MFA o regenerar tras pérdida).
      const ok = await checkRateLimit(admin, {
        bucketKey: `mfa-recovery-generate:user:${user.id}`,
        limit: 5,
        windowSeconds: 3600,
      });
      if (!ok) return json({ error: "rate_limited" }, 429);

      const codes: string[] = [];
      for (let i = 0; i < CODE_COUNT; i++) codes.push(generateCode());
      const rows = await Promise.all(
        codes.map(async (c) => ({
          user_id: user.id,
          code_hash: await sha256(normalize(c)),
        })),
      );

      // Reemplazar: borrar los antiguos e insertar los nuevos.
      const del = await admin
        .from("mfa_recovery_codes")
        .delete()
        .eq("user_id", user.id);
      if (del.error) {
        return json({ error: "delete_failed", detail: del.error.message }, 500);
      }
      const ins = await admin.from("mfa_recovery_codes").insert(rows);
      if (ins.error) {
        return json({ error: "insert_failed", detail: ins.error.message }, 500);
      }

      return json({ codes }, 200);
    }

    // ---- VERIFY ------------------------------------------------------------
    if (action === "verify") {
      // Rate limit: 10 intentos / 15 min por usuario — anti-fuerza bruta
      // de códigos. Usuarios legítimos suelen acertar a la primera o
      // segunda; 10 cubre fallos de copia/pega y deja inviable el
      // ataque (≈ 10⁻¹⁰ de probabilidad con 10 tries en una ventana).
      const ok = await checkRateLimit(admin, {
        bucketKey: `mfa-recovery-verify:user:${user.id}`,
        limit: 10,
        windowSeconds: 900,
      });
      if (!ok) return json({ error: "rate_limited" }, 429);

      const code = typeof body?.code === "string" ? body.code : "";
      if (normalize(code).length === 0) {
        return json({ error: "missing_code" }, 400);
      }
      const hash = await sha256(normalize(code));

      const { data: match, error: selErr } = await admin
        .from("mfa_recovery_codes")
        .select("id")
        .eq("user_id", user.id)
        .eq("code_hash", hash)
        .is("used_at", null)
        .maybeSingle();
      if (selErr) {
        return json({ error: "lookup_failed", detail: selErr.message }, 500);
      }
      if (!match) {
        return json({ error: "invalid_code" }, 401);
      }

      // Marcar el código como usado.
      const upd = await admin
        .from("mfa_recovery_codes")
        .update({ used_at: new Date().toISOString() })
        .eq("id", match.id);
      if (upd.error) {
        return json({ error: "consume_failed", detail: upd.error.message }, 500);
      }

      // Eliminar los factores MFA del usuario: así deja de requerirse AAL2.
      const { data: factorsData } = await admin.auth.admin.mfa.listFactors({
        userId: user.id,
      });
      const factors = factorsData?.factors ?? [];
      for (const f of factors) {
        await admin.auth.admin.mfa.deleteFactor({ id: f.id, userId: user.id });
      }

      // Cuántos códigos sin usar le quedan (informativo).
      const { count } = await admin
        .from("mfa_recovery_codes")
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id)
        .is("used_at", null);

      return json({ success: true, remaining: count ?? 0 }, 200);
    }

    return json({ error: "unknown_action" }, 400);
  } catch (e) {
    return json({ error: "internal_error", detail: String(e) }, 500);
  }
});
