// ============================================================================
// Edge Function: delete-account
// ----------------------------------------------------------------------------
// Borra de forma permanente la cuenta del usuario que la invoca.
//
// Por qué una Edge Function y no hacerlo desde la app:
//   - Eliminar un usuario de `auth.users` requiere la `service_role` key.
//   - Esa key NUNCA puede vivir en el cliente (daría acceso total a la BBDD).
//   - Aquí corre del lado servidor: Supabase la inyecta como variable de
//     entorno automáticamente (SUPABASE_SERVICE_ROLE_KEY).
//
// Seguridad:
//   - `verify_jwt` está activo por defecto → solo se puede invocar con un JWT
//     válido. Identificamos al usuario por SU PROPIO token y solo borramos a
//     ESE usuario. Nadie puede borrar la cuenta de otro.
//   - **PR-F**: ademas del JWT, exigimos que el user haya pasado por
//     `verify-password` con `action_kind='delete_account'` en los
//     ultimos 5 minutos. Sin ese marker fresco -> 403. Asi un atacante
//     con JWT robado NO puede borrar la cuenta saltandose el modal de
//     password (antes de PR-F, la proteccion de password era SOLO
//     client-side y se podia invocar este endpoint directo).
//   - La verificacion se CONSUME (delete) al usarse -> evita replays.
//
// Al borrar el usuario de `auth.users`, la fila de `public.profiles` (y
// cualquier tabla con FK `on delete cascade`) se elimina con él.
//
// Desplegar:  supabase functions deploy delete-account
// (ver supabase/ACCOUNT_DELETION_SETUP.md)
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
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(withSentry("delete-account", async (req) => {
  // Preflight CORS (la app web hace una petición OPTIONS primero).
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

    // Variables que Supabase inyecta automáticamente en toda Edge Function.
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // 1) Identificar al usuario que llama, usando SU token.
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

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Rate limit: 3 intentos / hora por usuario. La acción es destructiva
    // e infrecuente; un bot acumulando intentos no tiene caso de uso.
    const ok = await checkRateLimit(adminClient, {
      bucketKey: `delete-account:user:${user.id}`,
      limit: 3,
      windowSeconds: 3600,
    });
    if (!ok) return json({ error: "rate_limited" }, 429);

    // **PR-F**: confirmar re-auth fresca con password ANTES de borrar.
    // El cliente debe haber llamado a `verify-password` con
    // action_kind='delete_account' en los ultimos 5 min (TTL del RPC).
    // `consume_recent_verification` borra la fila si existe -> evita
    // replays. Si no hay verificacion fresca, 403.
    const { data: verified, error: vErr } = await adminClient.rpc(
      "consume_recent_verification",
      {
        p_action_kind: "delete_account",
        p_user_id: user.id,
      },
    );
    if (vErr) {
      return json({ error: "reauth_check_failed", detail: vErr.message }, 500);
    }
    if (verified !== true) {
      return json({ error: "reauth_required" }, 403);
    }

    // 2) Borrar ese usuario con el cliente admin (service_role).
    //    `public.profiles` se va por ON DELETE CASCADE.
    const { error: deleteErr } = await adminClient.auth.admin.deleteUser(
      user.id,
    );
    if (deleteErr) {
      return json({ error: "delete_failed", detail: deleteErr.message }, 500);
    }

    return json({ success: true }, 200);
  } catch (e) {
    return json({ error: "internal_error", detail: String(e) }, 500);
  }
}));
