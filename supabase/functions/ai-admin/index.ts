// ============================================================================
// Edge Function: ai-admin · Gestión segura de proveedores y credenciales de IA
// ----------------------------------------------------------------------------
// El superadmin gestiona desde aquí el registro de proveedores (on/off,
// prioridad, modelo, base_url) y sus API keys. CLAVE de seguridad: las keys
// viven en `ai_credentials` (tabla SOLO-servidor, RLS sin policies) y esta EF
// es la ÚNICA puerta. NUNCA devuelve la key completa: solo metadatos + un
// `key_last4` para preview enmascarada. La key se introduce (write-only) y, si
// hace falta, se rota borrando+creando.
//
// Gate de autorización: capability `manage_ai` (el super_admin pasa siempre,
// lo resuelve `has_capability`). Acciones via POST { action, ... }:
//   - list              -> proveedores + credenciales (SIN api_key)
//   - save_provider     -> { id, enabled?, priority?, default_model?, base_url?, notes?, tier? }
//   - add_credential    -> { provider_id, api_key, label? }
//   - update_credential -> { id, enabled?, label?, clear_cooldown? }
//   - delete_credential -> { id }
//   - test              -> { provider_id }  (hace una mini-llamada real)
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
import { checkCapability } from "../_shared/capability.ts";
import { AiGatewayError, runCompletion } from "../_shared/ai/gateway.ts";

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

// Columnas de credenciales que SÍ es seguro devolver (nunca `api_key`).
const CRED_PUBLIC_COLS =
  "id, provider_id, label, enabled, key_last4, disabled_reason, cooldown_until, last_used_at, created_at";

Deno.serve(withSentry("ai-admin", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // ─── Auth + capability gate ───
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  // `manage_ai` es el gate real (el super_admin pasa siempre vía has_capability).
  const capErr = await checkCapability(userClient, user.id, "manage_ai");
  if (capErr) return json({ error: capErr }, 403);

  const admin = createClient(supabaseUrl, serviceRoleKey);

  const body = await req.json().catch(() => null) as
    | Record<string, unknown>
    | null;
  if (!body || typeof body.action !== "string") {
    return json({ error: "bad_request" }, 400);
  }
  const action = body.action;

  try {
    switch (action) {
      case "list": {
        const { data: providers, error: pErr } = await admin
          .from("ai_providers")
          .select("*")
          .order("priority", { ascending: true });
        if (pErr) return json({ error: "db_error", detail: pErr.message }, 500);
        const { data: credentials, error: cErr } = await admin
          .from("ai_credentials")
          .select(CRED_PUBLIC_COLS)
          .order("created_at", { ascending: true });
        if (cErr) return json({ error: "db_error", detail: cErr.message }, 500);
        return json({
          ok: true,
          providers: providers ?? [],
          credentials: credentials ?? [],
        }, 200);
      }

      case "save_provider": {
        const id = body.id;
        if (typeof id !== "string") return json({ error: "missing_id" }, 400);
        const patch: Record<string, unknown> = {};
        for (const k of ["enabled", "priority", "default_model", "base_url", "notes", "tier"]) {
          if (k in body) patch[k] = body[k];
        }
        if (Object.keys(patch).length === 0) {
          return json({ error: "nothing_to_update" }, 400);
        }
        const { data, error } = await admin
          .from("ai_providers")
          .update(patch)
          .eq("id", id)
          .select("*")
          .single();
        if (error) return json({ error: "db_error", detail: error.message }, 500);
        return json({ ok: true, provider: data }, 200);
      }

      case "add_credential": {
        const providerId = body.provider_id;
        const apiKey = body.api_key;
        if (typeof providerId !== "string" || typeof apiKey !== "string" || apiKey.length < 8) {
          return json({ error: "missing_fields" }, 400);
        }
        const last4 = apiKey.slice(-4);
        const { data, error } = await admin
          .from("ai_credentials")
          .insert({
            provider_id: providerId,
            label: typeof body.label === "string" ? body.label : null,
            api_key: apiKey,
            key_last4: last4,
          })
          .select(CRED_PUBLIC_COLS)
          .single();
        if (error) return json({ error: "db_error", detail: error.message }, 500);
        return json({ ok: true, credential: data }, 200);
      }

      case "update_credential": {
        const id = body.id;
        if (typeof id !== "string") return json({ error: "missing_id" }, 400);
        const patch: Record<string, unknown> = {};
        if ("enabled" in body) patch.enabled = body.enabled;
        if ("label" in body) patch.label = body.label;
        if (body.clear_cooldown === true) {
          patch.cooldown_until = null;
          patch.disabled_reason = null;
        }
        if (Object.keys(patch).length === 0) {
          return json({ error: "nothing_to_update" }, 400);
        }
        const { error } = await admin
          .from("ai_credentials")
          .update(patch)
          .eq("id", id);
        if (error) return json({ error: "db_error", detail: error.message }, 500);
        return json({ ok: true }, 200);
      }

      case "delete_credential": {
        const id = body.id;
        if (typeof id !== "string") return json({ error: "missing_id" }, 400);
        const { error } = await admin
          .from("ai_credentials")
          .delete()
          .eq("id", id);
        if (error) return json({ error: "db_error", detail: error.message }, 500);
        return json({ ok: true }, 200);
      }

      case "test": {
        const providerId = body.provider_id;
        if (typeof providerId !== "string") {
          return json({ error: "missing_id" }, 400);
        }
        const { data: prov } = await admin
          .from("ai_providers")
          .select("slug")
          .eq("id", providerId)
          .maybeSingle();
        if (!prov) return json({ error: "provider_not_found" }, 404);
        try {
          const r = await runCompletion(admin, {
            task: "test",
            onlyProviderSlug: prov.slug as string,
            system: "You are a connectivity test. Reply with one short word.",
            messages: [{ role: "user", content: "Say OK." }],
            maxOutputTokens: 16,
            temperature: 0,
            userId: user.id,
          });
          return json({
            ok: true,
            provider: r.providerSlug,
            model: r.model,
            sample: r.text.slice(0, 200),
          }, 200);
        } catch (e) {
          const detail = e instanceof AiGatewayError
            ? e.message
            : (e as Error).message;
          // 200 con ok:false: el "test" siempre responde para que la UI muestre
          // el detalle del fallo (no es un error de la petición en sí).
          return json({ ok: false, error: "test_failed", detail }, 200);
        }
      }

      default:
        return json({ error: "unknown_action" }, 400);
    }
  } catch (e) {
    return json({ error: "server_error", detail: (e as Error).message }, 500);
  }
}));
