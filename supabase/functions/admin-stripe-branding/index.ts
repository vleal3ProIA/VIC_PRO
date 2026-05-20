// ============================================================================
// Edge Function: admin-stripe-branding (READ-ONLY)
// ----------------------------------------------------------------------------
// Devuelve el branding actual + business_profile de la propia cuenta Stripe
// de la plataforma. Solo lectura.
//
// CONTEXTO: originalmente quisimos exponer también update (colores, logo,
// business_profile) desde nuestro panel admin, pero Stripe **rechaza con
// 403** cualquier POST sobre la propia cuenta de plataforma:
//
//   "You cannot use this method on your own account: you may only use it
//    on connected accounts."
//
// Esto es política deliberada de Stripe — los settings de la cuenta propia
// se editan ÚNICAMENTE desde `https://dashboard.stripe.com/settings/branding`
// y `/settings/account`. No hay forma documentada vía API.
//
// Por eso esta función es read-only: el panel /admin/branding muestra los
// datos y un botón "Editar en Stripe Dashboard" que abre la pestaña
// correcta. El admin sigue ahorrándose el login a Stripe para ver el
// estado.
//
// Acción única:
//
//   { "action": "get" }
//     Devuelve { branding, business_profile } del own account.
//
// Seguridad:
//   - JWT + role=admin en profiles.
//   - Rate limit 30/h/user.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
import { getStripe, stripeNotConfigured } from "../_shared/stripe.ts";
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

Deno.serve(withSentry("admin-stripe-branding", async (req) => {
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
  // PR-Super-A3: capability gate (super pasa siempre).
  const capErr = await checkCapability(admin, user.id, "manage_branding");
  if (capErr) return json({ error: capErr }, 403);

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `stripe:branding:user:${user.id}`,
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

  if (action === "get") {
    try {
      const account = await stripe.accounts.retrieve();
      const branding = account.settings?.branding ?? {};
      // Si hay logo file_id, intentamos obtener su URL pública para
      // mostrarla como preview en la UI admin.
      let logoUrl: string | null = null;
      const logoFileId = branding.logo as string | null | undefined;
      if (logoFileId) {
        try {
          const fileLinks = await stripe.fileLinks.list({
            file: logoFileId,
            limit: 1,
          });
          if (fileLinks.data.length > 0) {
            logoUrl = fileLinks.data[0].url;
          } else {
            const link = await stripe.fileLinks.create({ file: logoFileId });
            logoUrl = link.url;
          }
        } catch (_) {
          // Si no podemos generar el link, no es bloqueante; la UI
          // simplemente no muestra preview.
        }
      }
      return json(
        {
          branding: {
            primary_color: branding.primary_color ?? null,
            secondary_color: branding.secondary_color ?? null,
            logo: logoFileId ?? null,
            logo_url: logoUrl,
            icon: branding.icon ?? null,
          },
          business_profile: account.business_profile ?? {},
        },
        200,
      );
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  return json({ error: "unknown_action" }, 400);
}));
