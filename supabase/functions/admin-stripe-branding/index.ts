// ============================================================================
// Edge Function: admin-stripe-branding
// ----------------------------------------------------------------------------
// Gestión del branding y datos fiscales de tu propia cuenta Stripe desde
// el panel admin de la app, sin tener que ir a dashboard.stripe.com.
//
// Lo que controlas:
//   - settings.branding.primary_color
//   - settings.branding.secondary_color
//   - settings.branding.logo (file_id)
//   - business_profile.name, support_email, url, support_phone,
//     support_address.{line1,city,postal_code,country}
//
// Estos campos se reflejan automáticamente en las facturas PDF y en
// las páginas hospedadas (Checkout, Customer Portal, invoice pages).
//
// Acciones:
//
//   { "action": "get" }
//     Devuelve estado actual del account (branding + business_profile).
//
//   { "action": "update_branding", "primary_color"?, "secondary_color"? }
//     PATCH a settings.branding (colores). Logo se actualiza en
//     upload_logo (porque requiere subir el archivo primero).
//
//   { "action": "update_business", "name"?, "support_email"?, "url"?,
//                                  "support_phone"?,
//                                  "support_address"? }
//     PATCH a business_profile.
//
//   { "action": "upload_logo", "filename", "mime_type", "data_base64" }
//     1) Sube el archivo a `stripe.files` con purpose=business_logo →
//        recibe file_id.
//     2) Update account.settings.branding.logo = file_id.
//
// Seguridad:
//   - JWT + role=admin en profiles.
//   - Rate limit 30/h/user.
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

  // ───────────────────────────────── GET ─────────────────────────────────

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

  // ──────────────────────────── UPDATE BRANDING ──────────────────────────

  if (action === "update_branding") {
    const primary = body.primary_color as string | undefined;
    const secondary = body.secondary_color as string | undefined;
    // Validación rápida: hex #RRGGBB.
    if (primary !== undefined && !/^#[0-9A-Fa-f]{6}$/.test(primary)) {
      return json({ error: "invalid_color", field: "primary_color" }, 400);
    }
    if (secondary !== undefined && !/^#[0-9A-Fa-f]{6}$/.test(secondary)) {
      return json({ error: "invalid_color", field: "secondary_color" }, 400);
    }
    try {
      // deno-lint-ignore no-explicit-any
      const brandingPatch: Record<string, any> = {};
      if (primary !== undefined) brandingPatch.primary_color = primary;
      if (secondary !== undefined) brandingPatch.secondary_color = secondary;
      if (Object.keys(brandingPatch).length === 0) {
        return json({ error: "nothing_to_update" }, 400);
      }
      const r = await updateOwnAccount({
        settings: { branding: brandingPatch },
      });
      if (r.error) {
        return json({ error: "stripe_error", detail: r.error }, 500);
      }
      return json({ ok: true }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  // ──────────────────────────── UPDATE BUSINESS ──────────────────────────

  if (action === "update_business") {
    const name = body.name as string | undefined;
    const supportEmail = body.support_email as string | undefined;
    const url = body.url as string | undefined;
    const supportPhone = body.support_phone as string | undefined;
    const supportAddress = body.support_address as
      | Record<string, string>
      | undefined;
    try {
      // deno-lint-ignore no-explicit-any
      const profile: Record<string, any> = {};
      if (name !== undefined) profile.name = name;
      if (supportEmail !== undefined) profile.support_email = supportEmail;
      if (url !== undefined) profile.url = url;
      if (supportPhone !== undefined) profile.support_phone = supportPhone;
      if (supportAddress !== undefined) profile.support_address = supportAddress;
      if (Object.keys(profile).length === 0) {
        return json({ error: "nothing_to_update" }, 400);
      }
      const r = await updateOwnAccount({ business_profile: profile });
      if (r.error) {
        return json({ error: "stripe_error", detail: r.error }, 500);
      }
      return json({ ok: true }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  // ────────────────────────────── UPLOAD LOGO ────────────────────────────

  if (action === "upload_logo") {
    const filename = body.filename as string | undefined;
    const mimeType = body.mime_type as string | undefined;
    const base64 = body.data_base64 as string | undefined;
    if (!filename || !mimeType || !base64) {
      return json({ error: "missing_fields" }, 400);
    }
    if (!["image/png", "image/jpeg", "image/gif", "image/webp"].includes(mimeType)) {
      return json({ error: "unsupported_mime" }, 400);
    }

    try {
      const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
      // Stripe limita logos a 4MB.
      if (bytes.byteLength > 4 * 1024 * 1024) {
        return json({ error: "file_too_large" }, 413);
      }

      // El SDK de Stripe para Node depende de librerías de multipart que NO
      // funcionan en Deno (`form-data`, streams Node). Subimos el fichero
      // con `fetch` directo a la Files API — es el patrón oficial para
      // entornos sin Node:
      //
      //   POST https://files.stripe.com/v1/files
      //   Authorization: Bearer <secret>
      //   Content-Type: multipart/form-data
      //   { purpose, file }
      const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")!;
      const form = new FormData();
      form.append("purpose", "business_logo");
      form.append("file", new Blob([bytes], { type: mimeType }), filename);

      const uploadRes = await fetch("https://files.stripe.com/v1/files", {
        method: "POST",
        headers: { Authorization: `Bearer ${stripeKey}` },
        body: form,
      });
      const uploadJson = await uploadRes.json();
      if (!uploadRes.ok) {
        const msg = uploadJson?.error?.message ?? `HTTP ${uploadRes.status}`;
        return json({ error: "stripe_error", detail: msg }, 500);
      }
      const fileId = uploadJson.id as string;

      // Asociar el file al account.settings.branding.logo.
      const linkRes = await updateOwnAccount({
        settings: { branding: { logo: fileId } },
      });
      if (linkRes.error) {
        return json({ error: "stripe_error", detail: linkRes.error }, 500);
      }

      // Crear link público para preview en la UI.
      let logoUrl: string | null = null;
      try {
        const link = await stripe.fileLinks.create({ file: fileId });
        logoUrl = link.url;
      } catch (_) {
        // No bloqueante.
      }

      return json({ ok: true, logo_file_id: fileId, logo_url: logoUrl }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  return json({ error: "unknown_action" }, 400);
}));

/// Stripe rechaza `accounts.update(<own_account_id>, ...)` con:
///   "You cannot use this method on your own account: you may only use it
///    on connected accounts."
///
/// Para actualizar la propia cuenta de plataforma hay que pegar contra
/// `POST https://api.stripe.com/v1/account` (sin id en la URL). El SDK
/// Node no expone esto cómodamente; lo hacemos con `fetch` directo.
///
/// Stripe usa form-urlencoded con corchetes para anidar — por ejemplo:
///   settings[branding][primary_color]=%231F2937
///   business_profile[support_address][city]=Madrid
///
/// Devuelve `{ok: true}` en éxito o `{error: <stripe message>}` en fallo.
async function updateOwnAccount(
  // deno-lint-ignore no-explicit-any
  payload: Record<string, any>,
): Promise<{ ok?: true; error?: string }> {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")!;
  const body = stripeFormEncode(payload);
  const res = await fetch("https://api.stripe.com/v1/account", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${stripeKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
  if (res.ok) return { ok: true };
  try {
    const j = await res.json();
    return { error: j?.error?.message ?? `HTTP ${res.status}` };
  } catch {
    return { error: `HTTP ${res.status}` };
  }
}

/// Serializa un objeto JS al formato form-urlencoded estilo Stripe:
///   { a: 1, b: { c: "x" }, d: ["y", "z"] }
///     →  a=1&b[c]=x&d[0]=y&d[1]=z   (con encodeURIComponent)
// deno-lint-ignore no-explicit-any
function stripeFormEncode(obj: Record<string, any>): string {
  const parts: string[] = [];
  // deno-lint-ignore no-explicit-any
  const walk = (value: any, prefix: string): void => {
    if (value === undefined || value === null) return;
    if (Array.isArray(value)) {
      value.forEach((v, i) => walk(v, `${prefix}[${i}]`));
    } else if (typeof value === "object") {
      for (const [k, v] of Object.entries(value)) {
        walk(v, `${prefix}[${k}]`);
      }
    } else {
      parts.push(
        `${encodeURIComponent(prefix)}=${encodeURIComponent(String(value))}`,
      );
    }
  };
  for (const [k, v] of Object.entries(obj)) walk(v, k);
  return parts.join("&");
}
