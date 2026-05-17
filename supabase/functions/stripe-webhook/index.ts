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
import { sendEmail } from "../_shared/email.ts";
import { fetchAppName, renderEmail } from "../_shared/email_templates.ts";

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

  // En Stripe API >= 2024-06 los `current_period_*` se movieron a
  // `subscription.items[0]`. Stripe los mantiene en el objeto raíz por
  // compatibilidad temporal pero pueden faltar en versiones nuevas
  // (p.ej. 2026-04-22.dahlia los devuelve solo en items). Leemos primero
  // del item; si no, fallback al campo legacy.
  // deno-lint-ignore no-explicit-any
  const firstItem = (sub.items as any)?.data?.[0] as
    | { current_period_start?: number; current_period_end?: number }
    | undefined;
  const currentPeriodStart = unixToIso(
    (firstItem?.current_period_start ?? sub.current_period_start) as
      | number
      | null,
  );
  const currentPeriodEnd = unixToIso(
    (firstItem?.current_period_end ?? sub.current_period_end) as number | null,
  );
  const trialEnd = unixToIso(sub.trial_end as number | null);
  const canceledAt = unixToIso(sub.canceled_at as number | null);
  const cancelAtPeriodEnd = (sub.cancel_at_period_end as boolean | null) ?? false;

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
    cancel_at_period_end: cancelAtPeriodEnd,
    stripe_subscription_id: stripeSubId,
    stripe_customer_id: sub.customer as string,
  };

  // Detectamos cambio de plan: la primera vez (no existing) SIEMPRE
  // es cambio (free -> paid); si hay existing y el plan_id cambia,
  // tambien lo es. Si solo cambian campos administrativos (status,
  // cancel_at_period_end, period dates por renovacion), NO mandamos
  // email para evitar spammar al user en cada ciclo de renovacion.
  let priorPlanId: string | undefined;
  if (existing) {
    const { data: existingFull } = await admin
      .from("tenant_subscriptions")
      .select("plan_id")
      .eq("id", existing.id)
      .maybeSingle();
    priorPlanId = existingFull?.plan_id as string | undefined;
  }
  const planChanged = !existing || priorPlanId !== planId;

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

    // Primera vez para este customer → sincronizamos los datos del
    // profile al Stripe customer para que la factura PDF salga con
    // nombre + dirección + tax id correctos. Best-effort.
    const createdByUserId = (sub.metadata as Record<string, string>)
      ?.created_by_user_id;
    if (createdByUserId && sub.customer) {
      await syncCustomerBillingInfo(
        admin,
        createdByUserId,
        sub.customer as string,
      );
    }
  }

  // Email "plan changed" al user que pago. Best-effort: si SMTP no
  // esta configurado o falla, NO bloqueamos el resto del webhook (la
  // suscripcion ya quedo persistida).
  if (planChanged && status === "active") {
    await dispatchPlanChangedEmail(admin, {
      tenantId,
      planId,
      periodEnd: currentPeriodEnd,
      createdByUserId: (sub.metadata as Record<string, string>)
        ?.created_by_user_id,
    }).catch((e) => {
      console.warn("dispatchPlanChangedEmail failed:", (e as Error).message);
    });
  }
}

/// Envia el email "plan changed" al user que pago. Lookup:
///   - el user_id viene del metadata `created_by_user_id` (lo setea
///     el flow de checkout cuando crea la sub).
///   - el email desde auth.users.
///   - el locale desde profiles.
///   - el plan_name desde public.plans.name.
async function dispatchPlanChangedEmail(
  admin: ReturnType<typeof createClient>,
  params: {
    tenantId: string;
    planId: string | undefined;
    periodEnd: string | null;
    createdByUserId: string | undefined;
  },
): Promise<void> {
  if (!params.createdByUserId || !params.planId) return;

  // Lookup user + locale (profile lo tiene; user.email viene de
  // auth.users via la vista admin).
  const { data: profile } = await admin
    .from("profiles")
    .select("locale")
    .eq("id", params.createdByUserId)
    .maybeSingle();
  // deno-lint-ignore no-explicit-any
  const { data: userData } = await (admin.auth as any).admin.getUserById(
    params.createdByUserId,
  );
  const userEmail = userData?.user?.email as string | undefined;
  if (!userEmail) return;

  const locale = (profile?.locale as string | undefined) ?? "en";

  // Lookup plan name.
  const { data: plan } = await admin
    .from("plans")
    .select("name")
    .eq("id", params.planId)
    .maybeSingle();
  const planName = (plan?.name as string | undefined) ?? "Plan";

  // App name + branding.
  const appName = await fetchAppName(admin);

  // URL al area de cliente: site_url + /billing/invoices.
  const siteUrl = Deno.env.get("SITE_URL")
    ?? Deno.env.get("PUBLIC_SITE_URL")
    ?? "";
  const actionUrl = siteUrl
    ? `${siteUrl.replace(/\/$/, "")}/billing/invoices`
    : "/billing/invoices";

  // Format period_end al locale del user. Usamos Intl.DateTimeFormat
  // que respeta el locale (ej. "15 de mayo de 2026" en es, "May 15,
  // 2026" en en).
  let periodEndFmt = "";
  if (params.periodEnd) {
    try {
      const d = new Date(params.periodEnd);
      periodEndFmt = new Intl.DateTimeFormat(locale, {
        dateStyle: "long",
      }).format(d);
    } catch (_) {
      periodEndFmt = params.periodEnd;
    }
  }

  const rendered = renderEmail({
    type: "plan_changed",
    locale,
    appName,
    data: {
      action_url: actionUrl,
      plan_name: planName,
      period_end: periodEndFmt,
    },
  });

  await sendEmail(admin, {
    type: "plan_changed",
    to: userEmail,
    toUserId: params.createdByUserId,
    locale,
    subject: rendered.subject,
    htmlBody: rendered.htmlBody,
    textBody: rendered.textBody,
    meta: {
      tenant_id: params.tenantId,
      plan_id: params.planId,
      plan_name: planName,
    },
  });
}

/// Lee el profile del user y actualiza name/address/tax_id en el Stripe
/// customer correspondiente. Idempotente. Si Stripe no está configurado
/// o falla, no abortamos — el resto del webhook ya quedó persistido.
async function syncCustomerBillingInfo(
  admin: ReturnType<typeof createClient>,
  userId: string,
  stripeCustomerId: string,
): Promise<void> {
  const stripe = getStripe();
  if (!stripe) return;
  try {
    const { data: profile } = await admin
      .from("profiles")
      .select(
        "first_name, last_name, address_line1, address_line2, city, " +
          "postal_code, country, tax_id, tax_id_type",
      )
      .eq("id", userId)
      .maybeSingle();
    if (!profile) return;
    const fullName = [profile.first_name, profile.last_name]
      .filter(Boolean)
      .join(" ");
    await stripe.customers.update(stripeCustomerId, {
      ...(fullName ? { name: fullName } : {}),
      ...(profile.address_line1
        ? {
            address: {
              line1: profile.address_line1 as string,
              line2: (profile.address_line2 as string | null) ?? undefined,
              city: (profile.city as string | null) ?? undefined,
              postal_code: (profile.postal_code as string | null) ?? undefined,
              country: (profile.country as string | null) ?? undefined,
            },
          }
        : {}),
    });
    if (profile.tax_id && profile.tax_id_type) {
      const existingTaxIds = await stripe.customers.listTaxIds(stripeCustomerId);
      const already = existingTaxIds.data.some(
        (t) => t.value === profile.tax_id,
      );
      if (!already) {
        await stripe.customers.createTaxId(stripeCustomerId, {
          type: profile.tax_id_type as Parameters<
            typeof stripe.customers.createTaxId
          >[1]["type"],
          value: profile.tax_id as string,
        });
      }
    }
  } catch (e) {
    console.warn(
      "syncCustomerBillingInfo failed:",
      (e as Error).message,
    );
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
