// ============================================================================
// Edge Function: admin-plans-prices
// ----------------------------------------------------------------------------
// Cambio de precio de un plan. Stripe Prices son **inmutables** — no se
// puede modificar `unit_amount`. La única forma de "cambiar el precio" es:
//
//   1. Crear NUEVOS Price objects en Stripe (mismo Product, otro amount).
//   2. Apuntar `plans.stripe_price_monthly/yearly` a los nuevos IDs.
//   3. Decidir qué hacer con las **suscripciones existentes** que ya pagan
//      el precio viejo:
//
//      a) `grandfather`     → no se toca nada. Los clientes existentes
//                             siguen pagando el viejo precio para siempre.
//                             Solo los NUEVOS contratos pagan el nuevo.
//      b) `next_period`     → al final del periodo actual, Stripe cambia
//                             al nuevo precio. Sin proration (el cliente
//                             ya pagó este periodo). Stripe lo gestiona
//                             via `subscriptions.update({proration_behavior:'none'})`
//                             cambiando el price del item — el efecto neto
//                             es el cambio en la próxima factura.
//      c) `immediate`       → cambio inmediato CON proration. Stripe
//                             cobra/abona la diferencia prorrateada por
//                             los días restantes del periodo.
//
// Acciones:
//
//   { "action": "preview", "plan_id" }
//     Devuelve { active_subscriptions_count } para que el admin sepa a
//     cuántos clientes afecta el cambio antes de aplicarlo. No toca nada.
//
//   { "action": "apply",
//     "plan_id": "<uuid>",
//     "new_price_monthly_cents"?: 1499,    // null = no cambia el mensual
//     "new_price_yearly_cents"?: 14990,    // null = no cambia el anual
//     "migration_strategy": "grandfather" | "next_period" | "immediate" }
//
//     1) Si Stripe no está configurado → error (operación sin sentido sin sync).
//     2) Por cada periodo modificado: lookup Product → crear Price nuevo.
//     3) UPDATE plans set stripe_price_monthly/yearly + price_*_cents.
//     4) Si strategy != grandfather → recorrer suscripciones activas del
//        plan y migrarlas con la API de Stripe.
//     5) Devuelve { migrated_count, errors[] } — best-effort: si una sub
//        falla, se loggea y se sigue. El admin puede reintentar.
//
// Seguridad: JWT + role=admin + rate limit 5/h (acción destructiva, no
// queremos accidentes ni abuso).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
import { getStripe, stripeNotConfigured } from "../_shared/stripe.ts";

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

const MIGRATION_STRATEGIES = ["grandfather", "next_period", "immediate"];

Deno.serve(withSentry("admin-plans-prices", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const stripe = getStripe();
  if (!stripe) return stripeNotConfigured();

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
  const { data: adminCheck } = await admin
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  if (!adminCheck || (adminCheck.role as string) !== "admin") {
    return json({ error: "not_admin" }, 403);
  }

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `admin:plans-prices:user:${user.id}`,
    limit: 5,
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
  const planId = body.plan_id as string | undefined;
  if (!planId) return json({ error: "missing_plan_id" }, 400);

  const { data: plan, error: planErr } = await admin
    .from("plans")
    .select(
      "id, slug, name, currency, price_monthly_cents, price_yearly_cents, " +
        "stripe_price_monthly, stripe_price_yearly, stripe_product_id",
    )
    .eq("id", planId)
    .maybeSingle();
  if (planErr) return json({ error: "db_error", detail: planErr.message }, 500);
  if (!plan) return json({ error: "plan_not_found" }, 404);

  // ──────────────────────────── PREVIEW ──────────────────────────────────

  if (action === "preview") {
    const { count } = await admin
      .from("tenant_subscriptions")
      .select("id", { count: "exact", head: true })
      .eq("plan_id", planId)
      .in("status", ["active", "trialing", "past_due"]);
    return json(
      {
        active_subscriptions_count: count ?? 0,
        current: {
          price_monthly_cents: plan.price_monthly_cents,
          price_yearly_cents: plan.price_yearly_cents,
          currency: plan.currency,
        },
      },
      200,
    );
  }

  // ───────────────────────────── APPLY ───────────────────────────────────

  if (action === "apply") {
    const newMonthly = body.new_price_monthly_cents as number | null | undefined;
    const newYearly = body.new_price_yearly_cents as number | null | undefined;
    const strategy = (body.migration_strategy as string | undefined) ??
      "grandfather";

    if (!MIGRATION_STRATEGIES.includes(strategy)) {
      return json({ error: "invalid_migration_strategy" }, 400);
    }
    if (newMonthly == null && newYearly == null) {
      return json({ error: "nothing_to_change" }, 400);
    }
    for (const v of [newMonthly, newYearly]) {
      if (v != null && (!Number.isInteger(v) || v <= 0)) {
        return json({ error: "invalid_price" }, 400);
      }
    }

    // Resolver el Stripe Product. Si plan.stripe_product_id está vacío
    // (planes antiguos), lo derivamos de uno de los price ids existentes.
    let productId = plan.stripe_product_id as string | null;
    if (!productId) {
      const referencePrice =
        (plan.stripe_price_monthly as string | null) ??
        (plan.stripe_price_yearly as string | null);
      if (!referencePrice) {
        return json({ error: "plan_not_billable_in_stripe" }, 400);
      }
      try {
        const p = await stripe.prices.retrieve(referencePrice);
        productId = typeof p.product === "string"
          ? p.product
          : (p.product as { id: string }).id;
      } catch (e) {
        return json(
          { error: "stripe_error", detail: (e as Error).message },
          500,
        );
      }
    }

    const currency = (plan.currency as string).toLowerCase();
    let newMonthlyPriceId: string | null = null;
    let newYearlyPriceId: string | null = null;

    try {
      if (newMonthly != null) {
        const created = await stripe.prices.create({
          product: productId,
          unit_amount: newMonthly,
          currency,
          recurring: { interval: "month" },
        });
        newMonthlyPriceId = created.id;
      }
      if (newYearly != null) {
        const created = await stripe.prices.create({
          product: productId,
          unit_amount: newYearly,
          currency,
          recurring: { interval: "year" },
        });
        newYearlyPriceId = created.id;
      }
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }

    // Guardamos los precios viejos para la migración.
    const oldMonthlyPriceId = plan.stripe_price_monthly as string | null;
    const oldYearlyPriceId = plan.stripe_price_yearly as string | null;

    // Update BD con los nuevos precios + IDs.
    const patch: Record<string, unknown> = {};
    if (newMonthlyPriceId) {
      patch.stripe_price_monthly = newMonthlyPriceId;
      patch.price_monthly_cents = newMonthly;
    }
    if (newYearlyPriceId) {
      patch.stripe_price_yearly = newYearlyPriceId;
      patch.price_yearly_cents = newYearly;
    }
    if (!plan.stripe_product_id && productId) {
      patch.stripe_product_id = productId;
    }
    const { error: updErr } = await admin
      .from("plans")
      .update(patch)
      .eq("id", planId);
    if (updErr) {
      // BD falló pero los Prices ya están creados en Stripe; quedan sin
      // referenciar. No es crítico — Stripe los mantiene. Reportamos.
      return json(
        {
          error: "db_error_after_stripe",
          detail: updErr.message,
          orphan_price_ids: [newMonthlyPriceId, newYearlyPriceId].filter(Boolean),
        },
        500,
      );
    }

    // Si la estrategia es grandfather, terminamos aquí.
    if (strategy === "grandfather") {
      return json(
        {
          ok: true,
          strategy,
          migrated_count: 0,
          errors: [],
          new_price_monthly: newMonthlyPriceId,
          new_price_yearly: newYearlyPriceId,
        },
        200,
      );
    }

    // Migración: para cada sub activa del plan, hacemos
    // subscriptions.update con el nuevo price. El proration depende de la
    // estrategia: next_period=none, immediate=create_prorations.
    const prorationBehavior = strategy === "immediate"
      ? "create_prorations"
      : "none";

    const { data: subs } = await admin
      .from("tenant_subscriptions")
      .select(
        "id, stripe_subscription_id, billing_period, status",
      )
      .eq("plan_id", planId)
      .in("status", ["active", "trialing", "past_due"]);

    let migrated = 0;
    const errors: Array<{ subscription_id: string; detail: string }> = [];
    for (const s of (subs ?? [])) {
      const subId = s.stripe_subscription_id as string | null;
      if (!subId) continue;
      const isYearly = (s.billing_period as string) === "yearly";
      const targetPriceId = isYearly ? newYearlyPriceId : newMonthlyPriceId;
      const sourcePriceId = isYearly ? oldYearlyPriceId : oldMonthlyPriceId;
      // Si no creamos nuevo price para este periodo, esta sub no se toca.
      if (!targetPriceId) continue;
      // Si el price no cambia (defensivo), tampoco la tocamos.
      if (sourcePriceId === targetPriceId) continue;

      try {
        // Necesitamos el id del SubscriptionItem para actualizar el price.
        const sub = await stripe.subscriptions.retrieve(subId);
        const item = sub.items.data[0];
        if (!item) {
          errors.push({ subscription_id: subId, detail: "no_items" });
          continue;
        }
        await stripe.subscriptions.update(subId, {
          items: [{ id: item.id, price: targetPriceId }],
          proration_behavior: prorationBehavior,
        });
        migrated++;
      } catch (e) {
        errors.push({
          subscription_id: subId,
          detail: (e as Error).message,
        });
      }
    }

    return json(
      {
        ok: true,
        strategy,
        migrated_count: migrated,
        errors,
        new_price_monthly: newMonthlyPriceId,
        new_price_yearly: newYearlyPriceId,
      },
      200,
    );
  }

  return json({ error: "unknown_action" }, 400);
}));
