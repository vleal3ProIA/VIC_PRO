// ============================================================================
// Helper compartido: cliente Stripe lazy + fail-soft
// ----------------------------------------------------------------------------
// Si `STRIPE_SECRET_KEY` no está configurado en las secrets de Supabase, las
// 3 Edge Functions de billing (checkout/webhook/portal) devolverán 503
// `stripe_not_configured` en lugar de crashear. Así el código se despliega
// hoy y el admin habilita Stripe cuando esté listo.
//
// Versión de la API fijada para que cambios futuros de Stripe no rompan
// silenciosamente. Hay que actualizarla a mano con awareness de migration
// notes de Stripe.
// ============================================================================

import Stripe from "https://esm.sh/stripe@17.4.0?target=deno";

let _stripe: Stripe | null = null;

/** `null` si Stripe no está configurado. Cachea el cliente. */
export function getStripe(): Stripe | null {
  if (_stripe) return _stripe;
  const key = Deno.env.get("STRIPE_SECRET_KEY");
  if (!key) return null;
  _stripe = new Stripe(key, {
    apiVersion: "2024-12-18.acacia",
    httpClient: Stripe.createFetchHttpClient(),
  });
  return _stripe;
}

/** Respuesta 503 estándar cuando Stripe falta. */
export function stripeNotConfigured(): Response {
  return new Response(
    JSON.stringify({ error: "stripe_not_configured" }),
    {
      status: 503,
      headers: { "content-type": "application/json" },
    },
  );
}

/**
 * Verifica la firma de un webhook con `STRIPE_WEBHOOK_SECRET`. Devuelve el
 * evento parseado o `null` si la firma no es válida.
 *
 * IMPORTANTE: hay que pasar el body **raw** (texto), no parsed JSON, porque
 * la firma se calcula sobre los bytes literales.
 */
export async function verifyWebhookSignature(
  rawBody: string,
  signature: string | null,
): Promise<Stripe.Event | null> {
  const stripe = getStripe();
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!stripe || !secret || !signature) return null;
  try {
    return await stripe.webhooks.constructEventAsync(
      rawBody,
      signature,
      secret,
    );
  } catch (e) {
    console.error("Stripe webhook signature failed:", e);
    return null;
  }
}
