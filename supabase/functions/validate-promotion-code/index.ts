// ============================================================================
// Edge Function: validate-promotion-code
// ----------------------------------------------------------------------------
// Endpoint público (requiere JWT autenticado, no admin) para que el flujo
// de checkout en /billing/plans valide un código promocional ANTES de
// iniciar el Stripe Checkout y muestre al cliente el descuento aplicado.
//
// La validación es contra nuestra BD vía la función SECURITY DEFINER
// `lookup_promotion_code(p_code text)`, que solo devuelve códigos que:
//   - existen
//   - están activos (`promotion_codes.is_active` y `coupons.is_active`)
//   - no han caducado (ni el cupón ni el código)
//   - no han agotado su tope de canjes
//
// Para evitar facilitar enumeración, cualquier código no encontrado o
// inválido devuelve la misma respuesta opaca `{valid: false}`. El cliente
// no puede distinguir "no existe" de "expirado" o "agotado".
//
// Request:
//   { "code": "VERANO2026", "plan_slug": "pro" }
//
// Response (success):
//   {
//     "valid": true,
//     "promotion_code_id": "<uuid>",
//     "stripe_promotion_code_id": "promo_xxx",  // para pasar al checkout
//     "code": "VERANO2026",
//     "discount": {
//       "percent_off": 20,            // o
//       "amount_off_cents": 500, "currency": "EUR",
//       "duration": "once|repeating|forever",
//       "duration_in_months": 3       // si repeating
//     },
//     "applies_to_plan_slugs": ["pro","team"] | null
//   }
//
// Response (invalid):
//   { "valid": false, "reason": "not_applicable_to_plan" | "not_found_or_expired" }
//
// Rate limit: 30/min/user para frenar enumeración por fuerza bruta. (30/min
// es generoso para un usuario real probando códigos, pero brutal para un
// bot que quisiera enumerar 8M de combinaciones de 8 caracteres.)
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

Deno.serve(withSentry("validate-promotion-code", async (req) => {
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

  // Rate limit con service-role (escribe en la tabla con bypass de RLS).
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `promo:validate:user:${user.id}`,
    limit: 30,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const code = (body.code as string | undefined)?.trim();
  const planSlug = (body.plan_slug as string | undefined)?.trim();
  if (!code) return json({ error: "missing_code" }, 400);

  // Llamamos la RPC con el user client — `lookup_promotion_code` es
  // SECURITY DEFINER, así que la propia función lee con privilegios
  // elevados pero el caller no puede ver el resto de las tablas.
  const { data, error } = await userClient.rpc("lookup_promotion_code", {
    p_code: code.toUpperCase(),
  });
  if (error) {
    return json({ error: "lookup_failed", detail: error.message }, 500);
  }

  const rows = (data ?? []) as Array<{
    promotion_code_id: string;
    code: string;
    first_time_transaction: boolean;
    coupon_id: string;
    coupon_name: string;
    percent_off: number | null;
    amount_off_cents: number | null;
    currency: string | null;
    duration: string;
    duration_in_months: number | null;
    applies_to_plan_slugs: string[] | null;
  }>;

  if (rows.length === 0) {
    return json({ valid: false, reason: "not_found_or_expired" }, 200);
  }
  const row = rows[0];

  // Restricción de plan si el cupón limita a slugs específicos.
  if (
    row.applies_to_plan_slugs &&
    row.applies_to_plan_slugs.length > 0 &&
    planSlug &&
    !row.applies_to_plan_slugs.includes(planSlug)
  ) {
    return json({ valid: false, reason: "not_applicable_to_plan" }, 200);
  }

  // Recuperamos el `stripe_promotion_code_id` para pasarlo al Checkout.
  // Lo necesitamos en otra query porque la RPC no lo expone (intencional:
  // así el cliente no puede usarlo para enumerar promos a saco).
  const { data: pcRow } = await admin
    .from("promotion_codes")
    .select("stripe_promotion_code_id")
    .eq("id", row.promotion_code_id)
    .maybeSingle();
  const stripePromoId = (pcRow?.stripe_promotion_code_id as string | null) ?? null;
  if (!stripePromoId) {
    // El código existe en BD pero no se sincronizó a Stripe. No utilizable
    // en el checkout; lo tratamos como inválido pero con un código distinto
    // para que el admin pueda diagnosticar si lo ve en logs.
    return json({ valid: false, reason: "not_synced" }, 200);
  }

  return json(
    {
      valid: true,
      promotion_code_id: row.promotion_code_id,
      stripe_promotion_code_id: stripePromoId,
      code: row.code,
      discount: {
        percent_off: row.percent_off,
        amount_off_cents: row.amount_off_cents,
        currency: row.currency,
        duration: row.duration,
        duration_in_months: row.duration_in_months,
      },
      applies_to_plan_slugs: row.applies_to_plan_slugs,
    },
    200,
  );
}));
