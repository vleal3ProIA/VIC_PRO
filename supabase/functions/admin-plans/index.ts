// ============================================================================
// Edge Function: admin-plans
// ----------------------------------------------------------------------------
// Operaciones admin sobre el catálogo de planes que necesitan tocar Stripe
// (las que solo tocan BD las hace el cliente directo vía RLS-admin).
//
// Acciones:
//
//   { "action": "update_metadata", "plan_id", "name", "description", "features", "position", "is_active" }
//     - Actualiza la fila en `plans` (campos no-precio)
//     - Sincroniza `name` y `description` con el Product de Stripe
//     - Backfillea `stripe_product_id` si falta (lookup vía price → product)
//     - Si is_active pasa a false, también archiva el product en Stripe
//
//   { "action": "backfill_product_ids" }
//     - Idempotente. Recorre los planes con `stripe_price_monthly` no null
//       y `stripe_product_id` null. Llama a Stripe para resolver el product.
//
// Seguridad:
//   - JWT requerido + admin global (`public.is_admin()`).
//   - Si Stripe no está configurado, las actualizaciones de BD siguen
//     funcionando (no es bloqueante). El sync de Stripe queda pendiente.
//
// La edición de PRECIOS (que es delicada — Stripe Prices son inmutables)
// queda fuera de esta función. La gestiona la futura `admin-plans-prices`
// en la PR 1.F.2.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
import { getStripe } from "../_shared/stripe.ts";
import { checkCapability } from "../_shared/capability.ts";

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

Deno.serve(withSentry("admin-plans", async (req) => {
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

  // user client → respeta RLS
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  // admin check vía RPC `is_admin()` con el user client (RLS aplica).
  // Si el usuario NO es admin, las queries devolverán 0 filas → 403.
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: adminCheck } = await admin
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  if (!adminCheck || (adminCheck.role as string) !== "admin") {
    return json({ error: "not_admin" }, 403);
  }
  // PR-Super-A3: capability gate (super pasa siempre).
  const capErr = await checkCapability(admin, user.id, "manage_plans");
  if (capErr) return json({ error: capErr }, 403);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const action = body.action as string | undefined;
  const stripe = getStripe(); // puede ser null → sync se omite

  // ───────────────────────────────── BACKFILL ─────────────────────────────

  if (action === "backfill_product_ids") {
    if (!stripe) return json({ skipped: "stripe_not_configured" }, 200);
    const { data: rows } = await admin
      .from("plans")
      .select("id, stripe_price_monthly, stripe_price_yearly, stripe_product_id")
      .is("stripe_product_id", null)
      .not("stripe_price_monthly", "is", null);
    let updated = 0;
    for (const row of rows ?? []) {
      const priceId = (row.stripe_price_monthly ?? row.stripe_price_yearly) as
        | string
        | null;
      if (!priceId) continue;
      try {
        const price = await stripe.prices.retrieve(priceId);
        const productId =
          typeof price.product === "string" ? price.product : price.product?.id;
        if (productId) {
          await admin
            .from("plans")
            .update({ stripe_product_id: productId })
            .eq("id", row.id);
          updated++;
        }
      } catch (e) {
        console.warn("backfill price retrieve failed:", (e as Error).message);
      }
    }
    return json({ updated }, 200);
  }

  // ───────────────────────────────── UPDATE ──────────────────────────────

  if (action === "update_metadata") {
    const planId = body.plan_id as string | undefined;
    if (!planId) return json({ error: "missing_plan_id" }, 400);

    const name = body.name as string | undefined;
    const description = body.description as string | null | undefined;
    const features = body.features as Record<string, unknown> | undefined;
    const position = body.position as number | undefined;
    const isActive = body.is_active as boolean | undefined;

    // Construimos el patch sin claves undefined.
    const patch: Record<string, unknown> = {};
    if (name !== undefined) patch.name = name;
    if (description !== undefined) patch.description = description;
    if (features !== undefined) patch.features = features;
    if (position !== undefined) patch.position = position;
    if (isActive !== undefined) patch.is_active = isActive;
    if (Object.keys(patch).length === 0) {
      return json({ error: "nothing_to_update" }, 400);
    }

    // 1) Actualizamos BD primero (verdad fuente).
    const { data: updated, error: updErr } = await admin
      .from("plans")
      .update(patch)
      .eq("id", planId)
      .select(
        "id, slug, name, description, features, position, is_active, " +
          "stripe_product_id, stripe_price_monthly, stripe_price_yearly",
      )
      .single();
    if (updErr) {
      return json({ error: "update_failed", detail: updErr.message }, 500);
    }

    // 2) Sync con Stripe (best-effort; si falla, el cliente lo verá en
    //    `stripe_sync_warning` pero el guardado ya está hecho).
    let stripeWarning: string | undefined;
    if (stripe) {
      try {
        // Backfill product_id si falta y tenemos algún price.
        let productId = updated.stripe_product_id as string | null;
        if (!productId) {
          const priceId =
            (updated.stripe_price_monthly ?? updated.stripe_price_yearly) as
              | string
              | null;
          if (priceId) {
            const price = await stripe.prices.retrieve(priceId);
            productId =
              typeof price.product === "string"
                ? price.product
                : price.product?.id ?? null;
            if (productId) {
              await admin
                .from("plans")
                .update({ stripe_product_id: productId })
                .eq("id", planId);
            }
          }
        }
        if (productId) {
          await stripe.products.update(productId, {
            ...(name !== undefined ? { name } : {}),
            ...(description !== undefined
              ? { description: description ?? undefined }
              : {}),
            ...(isActive !== undefined ? { active: isActive } : {}),
          });
        }
      } catch (e) {
        stripeWarning = (e as Error).message;
        console.warn("admin-plans stripe sync failed:", stripeWarning);
      }
    } else {
      stripeWarning = "stripe_not_configured";
    }

    return json({ plan: updated, stripe_sync_warning: stripeWarning }, 200);
  }

  return json({ error: "unknown_action" }, 400);
}));
