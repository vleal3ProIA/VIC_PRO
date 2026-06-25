// ============================================================================
// Helper compartido: envio de email via SMTP
// ----------------------------------------------------------------------------
// Wrapper sobre denomailer (cliente SMTP popular en Deno) que abstrae:
//   - conexion + cleanup
//   - timeouts
//   - logging en la tabla `email_log`
//
// La idea es que TODO email saliente de la app pase por `sendEmail()`,
// sin importar el origen (auth-email-hook, stripe-webhook, broadcast,
// test ping). Asi tenemos un solo punto donde:
//   1) cambiar el proveedor (SMTP → Resend → Postmark) sin tocar
//      callers
//   2) auditar TODOS los envios en `email_log`
//   3) controlar rate limits si hace falta
//
// **Variables de entorno requeridas** (configurar en Supabase
// Functions Settings, NO en .env del cliente):
//   - SMTP_HOST            host del proveedor (ej. smtp.dondominio.com)
//   - SMTP_PORT            465 (SSL) o 587 (STARTTLS)
//   - SMTP_USER            usuario SMTP (normalmente la direccion email)
//   - SMTP_PASSWORD        password de la cuenta
//   - SMTP_FROM            direccion remitente (ej. no-reply@tudominio.com)
//   - SMTP_FROM_NAME       nombre amigable (ej. "myapp")
//   - SMTP_USE_TLS         "true" si puerto 465 (default), "false" si 587
//
// Si SMTP_HOST no esta configurado, sendEmail() loguea como 'failed'
// con error 'smtp_not_configured' y devuelve sin lanzar. Asi el cliente
// puede seguir funcionando aunque el SMTP aun no este listo (util en
// dev local).
// ============================================================================

import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type EmailType =
  | "signup"
  | "recovery"
  | "magic_link"
  | "change_email"
  | "invite"
  | "plan_changed"
  | "broadcast"
  | "test"
  // Internal alerts emitted by `notify-super-admins` EF (PR 0074).
  // Differs from `broadcast` in that the template knows about the
  // specific event type (user.registered / user.role_changed /
  // user.deleted) via `data.event` and renders accordingly.
  | "super_admin_alert"
  // Daily-audit digest (PR 0080). Fired by `send-audit-digest` EF
  // after the maintenance cron finishes a run with triggered_by IS
  // NULL. One email per super-admin / admin recipient. Reuses the
  // `super_admin_alert` HTML wrapper for rendering; this is a
  // distinct EmailType only so we can filter / count digests in
  // email_log separately from generic super-admin alerts.
  | "audit_digest"
  // Error-report notification (PR 0083). Fired by `notify-error-report`
  // EF after an AFTER INSERT trigger on `error_reports`. One email per
  // super-admin / admin with capability `view_error_reports`. Same
  // wrapper as audit_digest; separate EmailType to enable filter /
  // count in `email_log`.
  | "error_report";

export interface SendEmailParams {
  type: EmailType;
  to: string;
  toUserId?: string | null;
  locale: string;
  subject: string;
  htmlBody: string;
  textBody?: string;
  meta?: Record<string, unknown>;
}

export interface SendEmailResult {
  ok: boolean;
  logId: string | null;
  error?: string;
}

/// Codifica un texto de cabecera (Subject, display-name del From) según RFC 2047
/// cuando tiene caracteres NO ASCII. Usa "encoded-words" base64 en UTF-8,
/// troceados en límites de carácter (≤45 bytes por palabra → ≤75 chars, como
/// exige el RFC). Si el texto es ASCII puro lo deja igual.
///
/// Por qué: denomailer 1.6.0 solo codifica cabeceras no-ASCII y su Q-encoding es
/// defectuoso (deja espacios literales dentro del encoded-word, inválido en
/// RFC 2047). Clientes estrictos (Apple Mail / iCloud) entonces no parsean el
/// mensaje y muestran el FUENTE en crudo, y el enlace de verificación no llega
/// usable. Pre-codificando a base64 ASCII, denomailer no toca la cabecera y el
/// asunto se decodifica bien en cualquier idioma (cirílico, acentos, etc.).
export function encodeHeaderText(text: string): string {
  // ASCII imprimible -> sin tocar (denomailer tampoco lo toca).
  if (/^[\x20-\x7E]*$/.test(text)) return text;
  const enc = new TextEncoder();
  const words: string[] = [];
  let buf: number[] = [];
  const flush = () => {
    if (buf.length === 0) return;
    let bin = "";
    for (const b of buf) bin += String.fromCharCode(b);
    words.push(`=?UTF-8?B?${btoa(bin)}?=`);
    buf = [];
  };
  for (const ch of text) {
    const chBytes = [...enc.encode(ch)];
    // No partir un carácter multibyte entre encoded-words (lo prohíbe RFC 2047).
    if (buf.length + chBytes.length > 45) flush();
    buf.push(...chBytes);
  }
  flush();
  return words.join(" ");
}

/**
 * Envia un email via SMTP y lo registra en `email_log`. Idempotente
 * desde el punto de vista del caller: nunca lanza. Si SMTP falla,
 * loguea `status='failed'` y devuelve `{ ok: false }`.
 *
 * @param admin Cliente Supabase con service_role (necesario para
 *              escribir en email_log que tiene RLS sin policies).
 */
export async function sendEmail(
  admin: SupabaseClient,
  params: SendEmailParams,
): Promise<SendEmailResult> {
  const {
    type,
    to,
    toUserId = null,
    locale,
    subject,
    htmlBody,
    textBody,
    meta = {},
  } = params;

  // 1) Crear row en email_log con status='queued'. Si SMTP falla mas
  //    abajo, lo actualizamos a 'failed' + error. Si va bien, a 'sent'.
  const { data: logRow, error: logErr } = await admin
    .from("email_log")
    .insert({
      type,
      to_email: to,
      to_user_id: toUserId,
      locale,
      subject,
      status: "queued",
      provider: "smtp",
      meta,
    })
    .select("id")
    .single();

  if (logErr || !logRow) {
    // No pudimos ni siquiera loguear. Devolvemos error sin intentar
    // enviar (probablemente RLS o conexion BD caida).
    return {
      ok: false,
      logId: null,
      error: `email_log_insert: ${logErr?.message ?? "unknown"}`,
    };
  }

  const logId = logRow.id as string;

  // 2) Validar config SMTP.
  const host = Deno.env.get("SMTP_HOST");
  const portStr = Deno.env.get("SMTP_PORT");
  const user = Deno.env.get("SMTP_USER");
  const password = Deno.env.get("SMTP_PASSWORD");
  const from = Deno.env.get("SMTP_FROM");
  const fromName = Deno.env.get("SMTP_FROM_NAME") ?? "myapp";
  const useTls = (Deno.env.get("SMTP_USE_TLS") ?? "true") !== "false";

  if (!host || !portStr || !user || !password || !from) {
    await admin
      .from("email_log")
      .update({ status: "failed", error: "smtp_not_configured" })
      .eq("id", logId);
    return { ok: false, logId, error: "smtp_not_configured" };
  }

  const port = Number.parseInt(portStr, 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    await admin
      .from("email_log")
      .update({ status: "failed", error: "smtp_invalid_port" })
      .eq("id", logId);
    return { ok: false, logId, error: "smtp_invalid_port" };
  }

  // 3) Conectar + enviar. denomailer soporta TLS implicito (465) y
  //    STARTTLS (587).
  const client = new SMTPClient({
    connection: {
      hostname: host,
      port,
      tls: useTls,
      auth: { username: user, password },
    },
  });

  try {
    await client.send({
      // Codificamos el display-name y el asunto (RFC 2047) para que los
      // idiomas con caracteres no-ASCII (cirílico, acentos…) lleguen bien.
      from: `${encodeHeaderText(fromName)} <${from}>`,
      to,
      subject: encodeHeaderText(subject),
      content: textBody ?? subject,
      html: htmlBody,
    });
    await client.close();
  } catch (e) {
    try {
      await client.close();
    } catch (_) {
      /* ignore close error after send error */
    }
    const msg = e instanceof Error ? e.message : String(e);
    await admin
      .from("email_log")
      .update({
        status: "failed",
        error: msg.slice(0, 500),
      })
      .eq("id", logId);
    return { ok: false, logId, error: msg };
  }

  // 4) Marcar como enviado.
  await admin
    .from("email_log")
    .update({ status: "sent", sent_at: new Date().toISOString() })
    .eq("id", logId);

  return { ok: true, logId };
}

/**
 * Helper para crear el admin client desde una Edge Function. Centralizado
 * para que todas las funciones que envian email usen el mismo patron.
 */
export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

// ============================================================================
// ASYNC QUEUE (migracion 0102) — para hot paths que NO pueden permitirse
// esperar al SMTP (caso paradigmatico: auth-email-hook dentro de la
// transaccion de signup).
// ----------------------------------------------------------------------------
// El caller invoca `enqueueEmail()` que solo escribe en `email_log` con
// status='queued' + cuerpo. La EF `email-drain` (llamada por pg_cron cada
// minuto) procesa la cola en lotes con conexion SMTP reutilizada.
// ============================================================================

/**
 * Encola un email para envio asincrono. Vuelve a llamar IDEMPOTENTE: no
 * abre SMTP, no espera red. Si el insert en email_log falla, devuelve
 * `{ok:false}` y el caller decide que hacer (en signup hook = devolver
 * 500 para que Supabase use template default).
 */
export async function enqueueEmail(
  admin: SupabaseClient,
  params: SendEmailParams,
): Promise<SendEmailResult> {
  const {
    type,
    to,
    toUserId = null,
    locale,
    subject,
    htmlBody,
    textBody,
    meta = {},
  } = params;
  const { data, error } = await admin
    .from("email_log")
    .insert({
      type,
      to_email: to,
      to_user_id: toUserId,
      locale,
      subject,
      html_body: htmlBody,
      text_body: textBody ?? null,
      status: "queued",
      provider: "smtp",
      meta,
    })
    .select("id")
    .single();
  if (error || !data) {
    return {
      ok: false,
      logId: null,
      error: `enqueue_failed: ${error?.message ?? "unknown"}`,
    };
  }
  return { ok: true, logId: data.id as string };
}

/**
 * Procesa la cola de emails encolados. Lee hasta `batchSize` filas con
 * status='queued' y next_try_at <= now() (o null), las envia via SMTP
 * REUTILIZANDO una sola conexion, y marca cada una sent/failed.
 *
 * Reintentos: si falla, incrementa `attempts` y programa `next_try_at`
 * con backoff (1min, 5min, 15min). Tras 3 intentos -> failed permanente.
 *
 * Llamado por `email-drain` EF (que a su vez la invoca pg_cron cada
 * minuto). Idempotente y safe to call concurrently — el SELECT FOR UPDATE
 * SKIP LOCKED garantiza que dos drainers en paralelo no procesen el
 * mismo email.
 */
export async function processEmailQueue(
  admin: SupabaseClient,
  batchSize = 20,
): Promise<{ sent: number; failed: number; skipped: number }> {
  const host = Deno.env.get("SMTP_HOST");
  const portStr = Deno.env.get("SMTP_PORT");
  const user = Deno.env.get("SMTP_USER");
  const password = Deno.env.get("SMTP_PASSWORD");
  const from = Deno.env.get("SMTP_FROM");
  const fromName = Deno.env.get("SMTP_FROM_NAME") ?? "myapp";
  const useTls = (Deno.env.get("SMTP_USE_TLS") ?? "true") !== "false";

  if (!host || !portStr || !user || !password || !from) {
    return { sent: 0, failed: 0, skipped: 0 };
  }
  const port = Number.parseInt(portStr, 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    return { sent: 0, failed: 0, skipped: 0 };
  }

  // RPC SQL `claim_queued_emails` hace el SELECT FOR UPDATE SKIP LOCKED
  // atomico para que multiples drainers no pisen filas. La RPC se define
  // en la migracion 0102.
  const { data: claimed, error: claimErr } = await admin
    .rpc("claim_queued_emails", { p_batch: batchSize });
  if (claimErr) {
    console.error("[processEmailQueue] claim failed:", claimErr.message);
    return { sent: 0, failed: 0, skipped: 0 };
  }
  const rows = (claimed ?? []) as Array<{
    id: string;
    to_email: string;
    subject: string;
    html_body: string | null;
    text_body: string | null;
    attempts: number;
  }>;
  if (rows.length === 0) return { sent: 0, failed: 0, skipped: 0 };

  // Reutilizamos UNA conexion SMTP para todo el lote — clave para no
  // saturar el pool del proveedor.
  const client = new SMTPClient({
    connection: {
      hostname: host,
      port,
      tls: useTls,
      auth: { username: user, password },
    },
  });

  let sent = 0;
  let failed = 0;
  for (const row of rows) {
    try {
      await client.send({
        from: `${encodeHeaderText(fromName)} <${from}>`,
        to: row.to_email,
        subject: encodeHeaderText(row.subject),
        content: row.text_body ?? row.subject,
        html: row.html_body ?? row.subject,
      });
      // Vaciamos cuerpos tras envio OK -> ahorra espacio.
      await admin.from("email_log").update({
        status: "sent",
        sent_at: new Date().toISOString(),
        html_body: null,
        text_body: null,
      }).eq("id", row.id);
      sent++;
    } catch (e) {
      const msg = (e instanceof Error ? e.message : String(e)).slice(0, 500);
      const attempts = row.attempts + 1;
      const final = attempts >= 3;
      const backoffMin = attempts === 1 ? 1 : attempts === 2 ? 5 : 15;
      const nextTry = new Date(Date.now() + backoffMin * 60_000).toISOString();
      await admin.from("email_log").update({
        status: final ? "failed" : "queued",
        attempts,
        last_error: msg,
        next_try_at: final ? null : nextTry,
      }).eq("id", row.id);
      failed++;
    }
  }
  try {
    await client.close();
  } catch (_) { /* ignore close error */ }
  return { sent, failed, skipped: 0 };
}
