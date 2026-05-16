// ============================================================================
// Edge Function: stripe-invoices
// ----------------------------------------------------------------------------
// Lista las facturas del Stripe customer del tenant. Sin Customer Portal.
//
// Acciones:
//
//   { "action": "list", "tenant_id", "limit?" }
//     Devuelve las últimas `limit` facturas (default 20, max 100) del
//     customer asociado al tenant.
//
//     Cada item:
//       {
//         id: 'in_xxx',
//         number: 'INV-0001',
//         status: 'paid' | 'open' | 'void' | ...,
//         amount_paid: 1900,         // céntimos
//         amount_due: 0,             // céntimos
//         currency: 'eur',
//         created: 1234567890,
//         hosted_invoice_url: 'https://invoice.stripe.com/i/xxx/yyy',
//         invoice_pdf: 'https://...stripe.com/files/.../invoice.pdf',
//         period_start: 1234,
//         period_end: 5678,
//       }
//
// Seguridad:
//   - JWT requerido; el caller debe ser miembro del tenant.
//   - Rate limit 30/h/user (listar facturas es operación admin frecuente).
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

Deno.serve(withSentry("stripe-invoices", async (req) => {
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
    bucketKey: `stripe:invoices:user:${user.id}`,
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

  if (body.action !== "list") {
    return json({ error: "unknown_action" }, 400);
  }

  const tenantId = body.tenant_id as string | undefined;
  if (!tenantId) return json({ error: "missing_tenant_id" }, 400);

  // Caller debe ser miembro del tenant (cualquier rol — ver facturas no
  // requiere admin; en muchos SaaS los miembros pueden ver el histórico
  // de pagos del workspace).
  const { data: membership } = await admin
    .from("tenant_members")
    .select("role")
    .eq("tenant_id", tenantId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!membership) return json({ error: "not_member" }, 403);

  // Buscar el stripe_customer_id del tenant.
  const { data: sub } = await admin
    .from("tenant_subscriptions")
    .select("stripe_customer_id")
    .eq("tenant_id", tenantId)
    .not("stripe_customer_id", "is", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const customerId = sub?.stripe_customer_id as string | undefined;
  if (!customerId) {
    // Tenant no ha pasado nunca por checkout → no hay facturas.
    return json({ invoices: [] }, 200);
  }

  const limit = Math.min(
    Math.max(parseInt(String(body.limit ?? 20), 10) || 20, 1),
    100,
  );

  try {
    const list = await stripe.invoices.list({
      customer: customerId,
      limit,
    });
    return json(
      {
        invoices: list.data.map((inv) => ({
          id: inv.id,
          number: inv.number,
          status: inv.status,
          amount_paid: inv.amount_paid,
          amount_due: inv.amount_due,
          amount_remaining: inv.amount_remaining,
          currency: inv.currency,
          created: inv.created,
          hosted_invoice_url: inv.hosted_invoice_url,
          invoice_pdf: inv.invoice_pdf,
          period_start: inv.period_start,
          period_end: inv.period_end,
        })),
      },
      200,
    );
  } catch (e) {
    return json(
      { error: "stripe_error", detail: (e as Error).message },
      500,
    );
  }
}));
