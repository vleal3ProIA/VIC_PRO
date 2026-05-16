// ============================================================================
// Edge Function: stripe-subscription-update
// ----------------------------------------------------------------------------
// Operaciones sobre una suscripción existente sin pasar por Stripe
// Customer Portal. Sustituye al portal para los casos comunes:
//
//   { "action": "change_plan", "subscription_id", "new_plan_slug", "new_billing_period" }
//     - Cambia plan y/o periodo de la sub viva.
//     - `proration_behavior: 'create_prorations'` → Stripe ajusta la
//       siguiente factura con el crédito/cargo proporcional.
//
//   { "action": "preview_change_plan", "subscription_id", "new_plan_slug", "new_billing_period" }
//     - Devuelve el invoice "upcoming" simulando el cambio. La UI lo
//       muestra al user antes de confirmar ("Se te cobrarán €X hoy").
//
//   { "action": "cancel", "subscription_id" }
//     - cancel_at_period_end=true. El user mantiene acceso hasta
//       current_period_end.
//
//   { "action": "reactivate", "subscription_id" }
//     - cancel_at_period_end=false (deshacer la cancelación pendiente).
//
//   { "action": "cancel_now", "subscription_id" }
//     - Cancela inmediatamente. NO reembolsamos por defecto (Stripe lo
//       puede gestionar manualmente desde su dashboard).
//
// Seguridad:
//   - JWT + el caller debe ser admin/owner del tenant dueño de la sub.
//   - Rate limit 30/h/user (operaciones administrativas frecuentes).
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

Deno.serve(withSentry("stripe-subscription-update", async (req) => {
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

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `stripe:sub-update:user:${user.id}`,
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
  const subscriptionId = body.subscription_id as string | undefined;
  if (!subscriptionId) return json({ error: "missing_subscription_id" }, 400);

  // Verifica que el caller es admin/owner del tenant dueño de esa sub.
  const { data: subRow } = await admin
    .from("tenant_subscriptions")
    .select("tenant_id")
    .eq("stripe_subscription_id", subscriptionId)
    .maybeSingle();
  if (!subRow) return json({ error: "subscription_not_found" }, 404);

  const { data: membership } = await admin
    .from("tenant_members")
    .select("role")
    .eq("tenant_id", subRow.tenant_id)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!membership) return json({ error: "not_member" }, 403);
  if (!["owner", "admin"].includes(membership.role as string)) {
    return json({ error: "not_admin" }, 403);
  }

  // ───────────────────────────────── CANCEL ──────────────────────────────

  if (action === "cancel") {
    try {
      const updated = await stripe.subscriptions.update(subscriptionId, {
        cancel_at_period_end: true,
      });
      return json({ ok: true, status: updated.status }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  // ─────────────────────────────── REACTIVATE ────────────────────────────

  if (action === "reactivate") {
    try {
      const updated = await stripe.subscriptions.update(subscriptionId, {
        cancel_at_period_end: false,
      });
      return json({ ok: true, status: updated.status }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  // ────────────────────────────── CANCEL NOW ─────────────────────────────

  if (action === "cancel_now") {
    try {
      await stripe.subscriptions.cancel(subscriptionId);
      return json({ ok: true }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  // ─────────────────────────── CHANGE PLAN / PREVIEW ─────────────────────

  if (action === "change_plan" || action === "preview_change_plan") {
    const newPlanSlug = body.new_plan_slug as string | undefined;
    const newBillingPeriod = body.new_billing_period as string | undefined;
    if (!newPlanSlug || !newBillingPeriod) {
      return json({ error: "missing_fields" }, 400);
    }
    if (!["monthly", "yearly"].includes(newBillingPeriod)) {
      return json({ error: "invalid_billing_period" }, 400);
    }

    const { data: newPlan } = await admin
      .from("plans")
      .select("id, stripe_price_monthly, stripe_price_yearly, is_active")
      .eq("slug", newPlanSlug)
      .maybeSingle();
    if (!newPlan) return json({ error: "plan_not_found" }, 404);
    if (!newPlan.is_active) return json({ error: "plan_not_active" }, 400);

    const newPriceId =
      newBillingPeriod === "yearly"
        ? newPlan.stripe_price_yearly
        : newPlan.stripe_price_monthly;
    if (!newPriceId) {
      return json({ error: "plan_not_billable" }, 400);
    }

    try {
      // Cargamos la sub para tener el subscription_item id (lo
      // necesitamos para mandar el "items[0].id" + "items[0].price").
      const sub = await stripe.subscriptions.retrieve(subscriptionId);
      const itemId = sub.items.data[0]?.id;
      if (!itemId) {
        return json({ error: "subscription_no_items" }, 500);
      }

      if (action === "preview_change_plan") {
        // Genera el invoice "upcoming" como si el cambio se aplicara YA.
        // El cliente lo usa para mostrar el cargo/crédito al usuario.
        const upcoming = await stripe.invoices.retrieveUpcoming({
          subscription: subscriptionId,
          subscription_items: [{ id: itemId, price: newPriceId }],
          subscription_proration_behavior: "create_prorations",
        });
        return json(
          {
            amount_due: upcoming.amount_due, // céntimos, puede ser negativo
            currency: upcoming.currency,
            next_payment_attempt: upcoming.next_payment_attempt,
            // Líneas individuales (útil si la UI quiere desglose).
            lines: upcoming.lines.data.map((l) => ({
              description: l.description,
              amount: l.amount,
            })),
          },
          200,
        );
      }

      // Apply.
      const updated = await stripe.subscriptions.update(subscriptionId, {
        items: [{ id: itemId, price: newPriceId }],
        proration_behavior: "create_prorations",
        metadata: {
          ...(sub.metadata ?? {}),
          plan_id: newPlan.id,
          plan_slug: newPlanSlug,
          billing_period: newBillingPeriod,
        },
      });
      return json({ ok: true, status: updated.status }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  return json({ error: "unknown_action" }, 400);
}));
