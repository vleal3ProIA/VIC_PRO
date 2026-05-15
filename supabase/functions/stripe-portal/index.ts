// ============================================================================
// Edge Function: stripe-portal
// ----------------------------------------------------------------------------
// Genera una sesión de Stripe Customer Portal y devuelve la URL para
// redirigir. Desde el portal el cliente puede:
//   - Actualizar método de pago
//   - Ver facturas
//   - Cancelar suscripción
//   - Cambiar de plan (si lo habilitas en la config del portal de Stripe)
//
// Body:
//   { tenant_id, return_url }
//
// Seguridad:
//   - JWT requerido; debe ser admin/owner del tenant.
//   - El tenant debe tener `stripe_customer_id` (haber pasado por checkout
//     al menos una vez).
//   - Rate limit: 20/hora/usuario.
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

Deno.serve(withSentry("stripe-portal", async (req) => {
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
    bucketKey: `stripe:portal:user:${user.id}`,
    limit: 20,
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
  const returnUrl = body.return_url as string | undefined;
  if (!tenantId || !returnUrl) return json({ error: "missing_fields" }, 400);

  // Caller debe ser admin/owner del tenant.
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

  // Customer ID de Stripe — el tenant tiene que haber hecho checkout antes.
  const { data: sub } = await admin
    .from("tenant_subscriptions")
    .select("stripe_customer_id")
    .eq("tenant_id", tenantId)
    .not("stripe_customer_id", "is", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const customerId = sub?.stripe_customer_id as string | undefined;
  if (!customerId) return json({ error: "no_customer" }, 400);

  try {
    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: returnUrl,
    });
    return json({ url: session.url }, 200);
  } catch (e) {
    return json(
      { error: "stripe_error", detail: (e as Error).message },
      500,
    );
  }
}));
