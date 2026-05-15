// ============================================================================
// Edge Function: stripe-webhook
// ----------------------------------------------------------------------------
// Recibe eventos de Stripe y sincroniza `tenant_subscriptions`.
//
// Eventos manejados:
//   - `customer.subscription.created`   → INSERT en tenant_subscriptions
//   - `customer.subscription.updated`   → UPDATE status/period/plan
//   - `customer.subscription.deleted`   → status=canceled + canceled_at=now
//   - `checkout.session.completed`      → primer set de stripe_customer_id
//
// Seguridad:
//   - **`verify_jwt = false`** en config.toml — Stripe NO manda JWT.
//   - La autenticidad se verifica firmando el body con `STRIPE_WEBHOOK_SECRET`
//     vía `stripe.webhooks.constructEvent`. Si la firma falla → 400.
//   - Idempotencia: cada `event.id` se inserta en `stripe_event_log`. Si ya
//     existe → 200 sin reaplicar.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
import {
  getStripe,
  stripeNotConfigured,
  verifyWebhookSignature,
} from "../_shared/stripe.ts";

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.serve(withSentry("stripe-webhook", async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const stripe = getStripe();
  if (!stripe) return stripeNotConfigured();

  // IMPORTANTE: leer body como texto raw. constructEvent NO acepta JSON
  // parseado — verifica la firma sobre los bytes literales.
  const rawBody = await req.text();
  const signature = req.headers.get("stripe-signature");
  const event = await verifyWebhookSignature(rawBody, signature);
  if (!event) return json({ error: "invalid_signature" }, 400);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  // ── Idempotencia ──
  // Intentamos insertar el id; si choca → ya procesado → 200 sin tocar nada.
  const payloadHash = await sha256Hex(rawBody);
  const { error: insErr } = await admin
    .from("stripe_event_log")
    .insert({
      id: event.id,
      type: event.type,
      api_version: event.api_version,
      payload_hash: payloadHash,
    });
  if (insErr) {
    // 23505 = unique_violation → ya estaba.
    if ((insErr as { code?: string }).code === "23505") {
      return json({ duplicate: true }, 200);
    }
    return json({ error: "log_failed", detail: insErr.message }, 500);
  }

  // ── Aplicación del evento ──
  try {
    switch (event.type) {
      case "customer.subscription.created":
      case "customer.subscription.updated":
        await handleSubscriptionUpserted(admin, event.data.object);
        break;
      case "customer.subscription.deleted":
        await handleSubscriptionDeleted(admin, event.data.object);
        break;
      case "checkout.session.completed":
        await handleCheckoutCompleted(admin, event.data.object);
        break;
      default:
        // Evento conocido por Stripe pero no nos interesa aún. Lo dejamos
        // registrado (ya está en stripe_event_log) por si lo queremos
        // procesar más tarde.
        break;
    }
  } catch (e) {
    return json(
      { error: "handler_failed", detail: (e as Error).message },
      500,
    );
  }

  return json({ received: true }, 200);
}));

// ─── Helpers ────────────────────────────────────────────────────────────────

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function handleSubscriptionUpserted(
  admin: ReturnType<typeof createClient>,
  sub: Record<string, unknown>,
) {
  const tenantId = (sub.metadata as Record<string, string> | undefined)
    ?.tenant_id;
  if (!tenantId) {
    console.warn("subscription without tenant_id metadata:", sub.id);
    return;
  }
  const planId =
    (sub.metadata as Record<string, string> | undefined)?.plan_id;
  const billingPeriod =
    (sub.metadata as Record<string, string> | undefined)?.billing_period ??
    "monthly";

  const status = mapStripeStatus(sub.status as string);
  const currentPeriodStart = unixToIso(sub.current_period_start as number);
  const currentPeriodEnd = unixToIso(sub.current_period_end as number);
  const trialEnd = unixToIso(sub.trial_end as number | null);
  const canceledAt = unixToIso(sub.canceled_at as number | null);

  // Buscar suscripción existente por stripe_subscription_id.
  const stripeSubId = sub.id as string;
  const { data: existing } = await admin
    .from("tenant_subscriptions")
    .select("id")
    .eq("stripe_subscription_id", stripeSubId)
    .maybeSingle();

  const row = {
    tenant_id: tenantId,
    plan_id: planId,
    status,
    billing_period: billingPeriod,
    current_period_start: currentPeriodStart,
    current_period_end: currentPeriodEnd,
    trial_end: trialEnd,
    canceled_at: canceledAt,
    stripe_subscription_id: stripeSubId,
    stripe_customer_id: sub.customer as string,
  };

  if (existing) {
    await admin
      .from("tenant_subscriptions")
      .update(row)
      .eq("id", existing.id);
  } else {
    // Antes de insertar, cancelamos cualquier suscripción "live" anterior
    // del mismo tenant: pasamos a 'canceled' la fila del plan free para que
    // el unique parcial no bloquee.
    await admin
      .from("tenant_subscriptions")
      .update({ status: "canceled", canceled_at: new Date().toISOString() })
      .eq("tenant_id", tenantId)
      .in("status", ["trialing", "active", "past_due", "incomplete"]);

    await admin.from("tenant_subscriptions").insert(row);
  }
}

async function handleSubscriptionDeleted(
  admin: ReturnType<typeof createClient>,
  sub: Record<string, unknown>,
) {
  await admin
    .from("tenant_subscriptions")
    .update({ status: "canceled", canceled_at: new Date().toISOString() })
    .eq("stripe_subscription_id", sub.id as string);
}

async function handleCheckoutCompleted(
  admin: ReturnType<typeof createClient>,
  session: Record<string, unknown>,
) {
  // Cuando completed llega antes que subscription.created, guardamos al
  // menos el customer_id en metadata del client_reference_id (tenant).
  const tenantId = session.client_reference_id as string | undefined;
  const customerId = session.customer as string | undefined;
  if (!tenantId || !customerId) return;
  // Solo update si NO hay suscripción ya creada (el flujo normal es:
  // checkout.completed → subscription.created en segundos).
  await admin
    .from("tenant_subscriptions")
    .update({ stripe_customer_id: customerId })
    .eq("tenant_id", tenantId)
    .is("stripe_customer_id", null);
}

function mapStripeStatus(s: string): string {
  switch (s) {
    case "trialing":
    case "active":
    case "past_due":
    case "canceled":
    case "incomplete":
      return s;
    case "incomplete_expired":
    case "unpaid":
      return "canceled";
    default:
      return "active";
  }
}

function unixToIso(s: number | null | undefined): string | null {
  if (!s) return null;
  return new Date(s * 1000).toISOString();
}
