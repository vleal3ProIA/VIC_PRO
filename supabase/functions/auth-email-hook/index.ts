// ============================================================================
// Edge Function: auth-email-hook
// ----------------------------------------------------------------------------
// Supabase Auth "Send Email Hook" (HTTP). Recibe los eventos de email
// de Supabase Auth (signup, recovery, magic_link, etc.) y los renderiza
// con NUESTRO sistema de templates + i18n + branding.
//
// **Como conectarlo en Supabase**:
//   1) Dashboard -> Authentication -> Hooks
//   2) Send Email Hook -> Enable -> tipo HTTPS
//   3) URL: https://<project>.supabase.co/functions/v1/auth-email-hook
//   4) Secret: copiar el "Webhook secret" que genera Supabase y
//      pegarlo como env var `AUTH_HOOK_SECRET` en Edge Functions settings.
//   5) Save.
//
// A partir de ese momento, Supabase NO enviara sus templates default;
// nos delegara A NOSOTROS la responsabilidad de mandar el email.
//
// **Payload** (segun Supabase docs):
//   {
//     "user": {
//       "id": "<uuid>",
//       "email": "user@example.com",
//       ...
//     },
//     "email_data": {
//       "token": "...",
//       "token_hash": "...",
//       "redirect_to": "https://...",
//       "email_action_type": "signup" | "recovery" | "invite" |
//                            "magiclink" | "email_change" |
//                            "email_change_current" | "email_change_new",
//       "site_url": "https://..."
//     }
//   }
//
// **Verificacion del webhook**: Supabase firma con HMAC-SHA256 los
// payloads. Validamos la firma en el header `webhook-signature` para
// evitar que cualquiera nos llame y mande emails arbitrarios.
//
// **Respuesta**: 200 con `{}` -> Supabase asume que enviamos el email.
// 4xx/5xx -> Supabase usa su template default como fallback (safety
// net por si nuestro SMTP falla).
// ============================================================================

import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { withSentry, captureError } from "../_shared/sentry.ts";
import { adminClient, EmailType, enqueueEmail } from "../_shared/email.ts";
import { fetchAppName, renderEmail } from "../_shared/email_templates.ts";

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

// Mapeo del email_action_type de Supabase a nuestros tipos internos.
function mapActionType(action: string): EmailType | null {
  switch (action) {
    case "signup":
      return "signup";
    case "recovery":
      return "recovery";
    case "magiclink":
      return "magic_link";
    case "invite":
      return "invite";
    case "email_change":
    case "email_change_current":
    case "email_change_new":
      return "change_email";
    default:
      return null;
  }
}

interface SupabaseEmailHookPayload {
  user: {
    id: string;
    email: string;
    new_email?: string;
    user_metadata?: { locale?: string; theme_mode?: string };
  };
  email_data: {
    token: string;
    token_hash: string;
    redirect_to: string;
    email_action_type: string;
    site_url: string;
  };
}

Deno.serve(withSentry("auth-email-hook", async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // ─────────────── Verificacion HMAC ───────────────
  const secret = Deno.env.get("AUTH_HOOK_SECRET");
  if (!secret) {
    // Sin secret configurado, rechazamos todo. Mejor 500 que dejar
    // un endpoint que cualquier internet podria llamar.
    await captureError(
      new Error("AUTH_HOOK_SECRET not set"),
      { fn: "auth-email-hook" },
    );
    return json({ error: "hook_not_configured" }, 500);
  }

  const rawBody = await req.text();
  const headers = {
    "webhook-id": req.headers.get("webhook-id") ?? "",
    "webhook-timestamp": req.headers.get("webhook-timestamp") ?? "",
    "webhook-signature": req.headers.get("webhook-signature") ?? "",
  };

  let payload: SupabaseEmailHookPayload;
  try {
    // Supabase usa Standard Webhooks (https://www.standardwebhooks.com/).
    // El secret que genera el dashboard viene como `v1,whsec_<base64>`, pero
    // standardwebhooks@1.0.0 SOLO reconoce el prefijo `whsec_` (no `v1,`):
    // si le pasas el `v1,` lo mete en el base64 -> clave erronea -> la firma
    // nunca valida -> 401 -> Supabase hace fallar el signup con 500. Por eso
    // quitamos el `v1,` antes de pasarlo.
    const wh = new Webhook(secret.replace(/^v1,/, ""));
    payload = wh.verify(rawBody, headers) as SupabaseEmailHookPayload;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[auth-email-hook] verify FAILED:", msg);
    await captureError(
      e instanceof Error ? e : new Error(String(e)),
      { fn: "auth-email-hook", step: "verify" },
    );
    return json({ error: "invalid_signature" }, 401);
  }
  console.log(
    "[auth-email-hook] verify OK, action=",
    payload.email_data.email_action_type,
  );

  // ─────────────── Decide qué email enviar ───────────────
  const type = mapActionType(payload.email_data.email_action_type);
  if (!type) {
    // Tipo desconocido — devolvemos 200 vacio sin enviar nada.
    // Supabase NO usara su template default porque le decimos OK.
    // Esto es deliberado: si alguna vez añaden un tipo nuevo, mejor
    // silencio que spam con un template fallback en ingles.
    return json({}, 200);
  }

  // Locale del user. Lo leemos de profiles (mantenido por el
  // ProfilePreferencesSync de Flutter). Si no esta, usamos 'en'.
  const admin = adminClient();
  const { data: profile } = await admin
    .from("profiles")
    .select("locale, theme_mode")
    .eq("id", payload.user.id)
    .maybeSingle();
  const locale = profile?.locale ?? payload.user.user_metadata?.locale ?? "en";
  // Modo claro/oscuro: preferencia GUARDADA del user (profiles.theme_mode);
  // si es nuevo, el theme_mode que paso el signUp en metadata; si no, 'system'
  // (el email se adapta al cliente de correo).
  const themeMode = profile?.theme_mode ??
    payload.user.user_metadata?.theme_mode ??
    "system";

  // App name desde el branding singleton.
  const appName = await fetchAppName(admin);

  // ─────────────── Construir action_url ───────────────
  // Supabase nos da el token; lo combinamos con el site_url + el
  // path estandar `/auth/v1/verify` o `/auth/callback`. Usamos el
  // helper recomendado: site_url + path + query con token_hash + type
  // + redirect_to.
  // Para un ENLACE clicable se usa `token_hash` (no `token`, que es el OTP de
  // 6 digitos para entrada manual). Fallback a token por si token_hash viniera
  // vacio. El verify endpoint de Supabase resuelve el hash y redirige a
  // redirect_to con la sesion en el fragmento.
  const verifyToken = payload.email_data.token_hash || payload.email_data.token;
  const params = new URLSearchParams({
    token: verifyToken,
    type: payload.email_data.email_action_type,
    redirect_to: payload.email_data.redirect_to,
  });
  // El endpoint /auth/v1/verify vive en el dominio de SUPABASE (la API),
  // NO en site_url (que es testexamen.es -> Apache -> index.html, link roto).
  // SUPABASE_URL lo inyecta el runtime de Edge Functions automaticamente.
  const verifyBase = Deno.env.get("SUPABASE_URL") ?? payload.email_data.site_url;
  const actionUrl = `${verifyBase}/auth/v1/verify?${params.toString()}`;
  console.log(
    "[auth-email-hook] actionUrl=", actionUrl,
    "| verifyBase=", verifyBase,
    "| token_hash.len=", payload.email_data.token_hash?.length ?? 0,
  );

  // Datos especificos por tipo.
  const data: Record<string, string> = {
    action_url: actionUrl,
  };
  if (type === "change_email") {
    data.new_email = payload.user.new_email ?? payload.user.email;
  }
  // Para 'invite' Supabase no nos pasa tenant_name; lo dejamos vacio y
  // el template caera al texto generico. Si quieres tenants en el
  // invite email, lo mejor es mandar tu propio invite via send-email
  // desde la Edge Function de tenant-invitations (que sabe el tenant).

  // ─────────────── Render + ENQUEUE (no SMTP aqui) ───────────────
  // CAMBIO M3 (migracion 0102): ya no enviamos SMTP dentro de la transaccion
  // del signup. Solo encolamos en email_log status='queued' (~1ms) y la EF
  // `email-drain` (llamada por pg_cron cada minuto) lo enviara reusando
  // conexion SMTP. Esto desatasca cientos de signups concurrentes que antes
  // saturaban el pool de SMTP de Dondominio.
  const rendered = renderEmail({ type, locale, appName, data, mode: themeMode });
  const result = await enqueueEmail(admin, {
    type,
    to: payload.user.email,
    // NO referenciamos al user por FK: en signup el row de auth.users AUN no
    // esta commiteado cuando corre este hook -> insertar to_user_id violaria
    // la FK. Guardamos el id en meta para trazar.
    toUserId: null,
    locale,
    subject: rendered.subject,
    htmlBody: rendered.htmlBody,
    textBody: rendered.textBody,
    meta: {
      via: "auth-hook",
      action: payload.email_data.email_action_type,
      user_id: payload.user.id,
    },
  });

  // Si fallo el enqueue (BD caida, RLS, etc.) devolvemos error -> Supabase
  // usa su template default como fallback.
  if (!result.ok) {
    console.error("[auth-email-hook] enqueue FAILED:", result.error);
    return json({ error: result.error ?? "enqueue_failed" }, 500);
  }
  // Sin PII en logs (M-Sec): solo log_id + locale + accion.
  console.log("[auth-email-hook] enqueued",
    "log_id=", result.logId,
    "action=", payload.email_data.email_action_type,
    "locale=", locale,
  );

  return json({}, 200);
}));
