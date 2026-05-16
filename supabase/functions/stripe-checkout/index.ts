// ============================================================================
// Edge Function: stripe-checkout
// ----------------------------------------------------------------------------
// Crea una sesión de Stripe Checkout y devuelve la URL para redirigir.
//
// Body:
//   {
//     tenant_id:      uuid,
//     plan_slug:      "pro" | "business",
//     billing_period: "monthly" | "yearly",
//     success_url:    "https://app/billing/success?session_id={CHECKOUT_SESSION_ID}",
//     cancel_url:     "https://app/billing/plans"
//   }
//
// Seguridad:
//   - Requiere JWT del usuario. Debe ser **admin/owner** del tenant.
//   - El plan_slug debe existir, estar activo y NO ser custom-priced
//     (enterprise se contacta a mano).
//   - Rate limit: 10/hora/usuario.
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

Deno.serve(withSentry("stripe-checkout", async (req) => {
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

  // Identifica al caller via su JWT (RLS aplica).
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  // Service-role para operaciones cross-tenant.
  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Rate limit por usuario para que nadie inunde Stripe.
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `stripe:checkout:user:${user.id}`,
    limit: 10,
    windowSeconds: 3600,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const tenantId = body.tenant_id as string | undefined;
  const planSlug = body.plan_slug as string | undefined;
  const billingPeriod = body.billing_period as string | undefined;
  const successUrl = body.success_url as string | undefined;
  const cancelUrl = body.cancel_url as string | undefined;

  if (!tenantId || !planSlug || !billingPeriod || !successUrl || !cancelUrl) {
    return json({ error: "missing_fields" }, 400);
  }
  if (!["monthly", "yearly"].includes(billingPeriod)) {
    return json({ error: "invalid_billing_period" }, 400);
  }

  // El caller debe ser admin/owner del tenant.
  const { data: membership } = await admin
    .from("tenant_members")
    .select("role")
    .eq("tenant_id", tenantId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!membership) return json({ error: "not_member" }, 403);
  if (!["owner", "admin"].includes(membership.role as string)) {
    return json({ error: "not_admin" }, 403);
  }

  // Lookup del plan + price id.
  const { data: plan } = await admin
    .from("plans")
    .select("id, slug, stripe_price_monthly, stripe_price_yearly, is_active")
    .eq("slug", planSlug)
    .maybeSingle();
  if (!plan) return json({ error: "plan_not_found" }, 404);
  if (!plan.is_active) return json({ error: "plan_not_active" }, 400);

  const priceId =
    billingPeriod === "yearly"
      ? plan.stripe_price_yearly
      : plan.stripe_price_monthly;
  if (!priceId) {
    return json({ error: "plan_not_billable", detail: "missing stripe price id" }, 400);
  }

  // Lookup existing Stripe customer_id si lo tenemos. Si no, dejamos que
  // Stripe Checkout lo cree y usaremos el ID de vuelta vía webhook.
  // OJO: existingSub puede tener `stripe_customer_id = null` (tenants
  // creados antes del primer checkout). Convertimos null → undefined para
  // que NO aparezca en el body de la request a Stripe (Stripe rechaza si
  // ve `customer` Y `customer_email` ambos presentes, aunque uno sea null).
  const { data: existingSub } = await admin
    .from("tenant_subscriptions")
    .select("stripe_customer_id")
    .eq("tenant_id", tenantId)
    .not("stripe_customer_id", "is", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const customerId = existingSub?.stripe_customer_id as string | undefined;

  // Construimos los params condicionalmente: o pasamos `customer` (cliente
  // Stripe ya creado), o pasamos `customer_email` (Stripe lo crea), pero
  // **nunca los dos**.
  const sessionParams: Record<string, unknown> = {
    mode: "subscription",
    success_url: successUrl,
    cancel_url: cancelUrl,
    line_items: [{ price: priceId, quantity: 1 }],
    // Metadata: imprescindible para que el webhook sepa a qué tenant
    // aplicar la suscripción creada.
    subscription_data: {
      metadata: {
        tenant_id: tenantId,
        plan_id: plan.id,
        plan_slug: planSlug,
        billing_period: billingPeriod,
        created_by_user_id: user.id,
      },
    },
    client_reference_id: tenantId,
    allow_promotion_codes: true,
  };
  if (customerId) {
    sessionParams.customer = customerId;
  } else if (user.email) {
    sessionParams.customer_email = user.email;
  }

  try {
    // deno-lint-ignore no-explicit-any
    const session = await stripe.checkout.sessions.create(sessionParams as any);
    return json({ url: session.url, session_id: session.id }, 200);
  } catch (e) {
    return json(
      { error: "stripe_error", detail: (e as Error).message },
      500,
    );
  }
}));
