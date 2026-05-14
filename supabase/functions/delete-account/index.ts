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
//   - La app, además, reautentica con contraseña antes de invocar esto.
//
// Al borrar el usuario de `auth.users`, la fila de `public.profiles` (y
// cualquier tabla con FK `on delete cascade`) se elimina con él.
//
// Desplegar:  supabase functions deploy delete-account
// (ver supabase/ACCOUNT_DELETION_SETUP.md)
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

Deno.serve(async (req) => {
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

    // 2) Borrar ese usuario con el cliente admin (service_role).
    //    `public.profiles` se va por ON DELETE CASCADE.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
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
});
