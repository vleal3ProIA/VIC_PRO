// ============================================================================
// Edge Function: broadcast-dispatch
// ----------------------------------------------------------------------------
// Procesa el envio de un broadcast en BATCHES con auto-resume:
//
//   1) Admin pulsa "Send" en /admin/broadcasts/new -> el cliente llama
//      con `action: 'start'`. Creamos el row 'sending', calculamos
//      recipients_total, procesamos el PRIMER batch.
//
//   2) Si quedan mas users por procesar y nos quedan < 30s de tiempo
//      de ejecucion, auto-invocamos a esta misma funcion con
//      `action: 'continue', broadcast_id: <id>`. Asi evitamos el
//      timeout duro de Supabase Edge Functions (~5 min) y podemos
//      procesar audiencias de cualquier tamaño.
//
//   3) Para audiencias chicas (< 100 users), todo cabe en una sola
//      invocacion.
//
// **Acciones**:
//   - `start`:     body: { subject, body_html, target_type, target_value }
//                   -> crea broadcast + envia primer batch
//   - `continue`:  body: { broadcast_id }  -> envia siguiente batch
//                   (solo callable por service_role)
//   - `test`:      body: { subject, body_html, to_email, locale }
//                   -> envia 1 email de prueba sin tocar tabla broadcasts
//
// **Auth**: admin via JWT (start, test); service_role via X-Internal-Auth
// (continue, llamado por nosotros mismos).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry, captureError } from "../_shared/sentry.ts";
import { adminClient, sendEmail } from "../_shared/email.ts";
import { fetchAppName, renderEmail } from "../_shared/email_templates.ts";
import { cleanBroadcastHtml } from "../_shared/html_sanitize.ts";
import { checkCapability } from "../_shared/capability.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-internal-auth",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

const BATCH_SIZE = 50;
// Margen de seguridad: si el tiempo restante (desde el start) es menor
// a este, paramos y delegamos al siguiente continue.
const MAX_FUNCTION_RUNTIME_MS = 4 * 60 * 1000; // 4 min de los ~5 del cap

Deno.serve(withSentry("broadcast-dispatch", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const action = body.action as string | undefined;
  if (!action) return json({ error: "missing_action" }, 400);

  const admin = adminClient();

  // ─────────────── Auth: admin JWT o service_role ───────────────
  const internalAuth = req.headers.get("X-Internal-Auth");
  const isInternal = internalAuth === serviceRoleKey;

  let adminUserId: string | null = null;
  if (!isInternal) {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "missing_authorization" }, 401);
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "invalid_token" }, 401);
    const { data: profile } = await userClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();
    if (profile?.role !== "admin") return json({ error: "forbidden" }, 403);
    // PR-Super-A3: capability gate (super pasa siempre). Solo aplica en
    // la rama de user real -- la rama isInternal (cron / dispatch del
    // sistema) NO pasa por aqui y no requiere capability.
    const capErr = await checkCapability(userClient, user.id, "manage_broadcasts");
    if (capErr) return json({ error: capErr }, 403);
    adminUserId = user.id;
  }

  // ─────────────────────────── TEST ─────────────────────────────
  if (action === "test") {
    if (isInternal) return json({ error: "forbidden" }, 403);
    const subject = (body.subject as string | undefined)?.trim();
    const bodyHtmlRaw = (body.body_html as string | undefined)?.trim();
    const to = body.to_email as string | undefined;
    const locale = (body.locale as string | undefined) ?? "en";
    if (!subject || !bodyHtmlRaw || !to) {
      return json({ error: "missing_fields" }, 400);
    }
    // PR-E: sanitize antes de renderizar para que el admin vea en el
    // test el mismo HTML que recibira la audiencia real (consistencia)
    // y para no enviarse a si mismo un payload peligroso.
    const bodyHtml = cleanBroadcastHtml(bodyHtmlRaw);
    if (!bodyHtml.trim()) {
      return json({ error: "body_html_empty_after_sanitize" }, 400);
    }
    const appName = await fetchAppName(admin);
    const rendered = renderEmail({
      type: "broadcast",
      locale,
      appName,
      data: { subject, body: bodyHtml },
    });
    const result = await sendEmail(admin, {
      type: "broadcast",
      to,
      toUserId: adminUserId,
      locale,
      subject: rendered.subject,
      htmlBody: rendered.htmlBody,
      textBody: rendered.textBody,
      meta: { test: true, sent_by_admin: adminUserId },
    });
    return json(
      { ok: result.ok, log_id: result.logId, error: result.error },
      200,
    );
  }

  // ─────────────────────────── START ────────────────────────────
  if (action === "start") {
    if (isInternal) return json({ error: "forbidden" }, 403);
    const subject = (body.subject as string | undefined)?.trim();
    const bodyHtmlRaw = (body.body_html as string | undefined)?.trim();
    const targetType = body.target_type as string | undefined;
    const targetValue =
      (body.target_value as Record<string, unknown> | undefined) ?? {};
    if (!subject || !bodyHtmlRaw || !targetType) {
      return json({ error: "missing_fields" }, 400);
    }
    if (!["all", "plan", "language", "status"].includes(targetType)) {
      return json({ error: "invalid_target_type" }, 400);
    }
    // PR-E: sanitize HTML server-side ANTES de persistir. El admin
    // podria tener cookie robada o ser malicioso; aceptar el HTML
    // crudo y mandarselo a toda la base es vector de phishing.
    // Whitelist estricta de tags+attrs (ver _shared/html_sanitize.ts).
    // Lo persistimos ya saneado para que NO haya que volver a
    // sanitizar en cada batch del processBroadcast loop.
    const bodyHtml = cleanBroadcastHtml(bodyHtmlRaw);
    if (!bodyHtml.trim()) {
      // Si tras sanitize no queda nada util (admin puso solo <script>
      // y similares), rechazamos: el broadcast saldria vacio.
      return json({ error: "body_html_empty_after_sanitize" }, 400);
    }

    // 1) Estimar la audiencia.
    const { data: est } = await admin.rpc("admin_broadcast_estimate", {
      p_target_type: targetType,
      p_target_value: targetValue,
    });
    const recipientsTotal = (est as { count?: number } | null)?.count ?? 0;

    // 2) Crear row 'sending' con el snapshot del count.
    const { data: row, error: insErr } = await admin
      .from("broadcasts")
      .insert({
        subject,
        body_html: bodyHtml,
        target_type: targetType,
        target_value: targetValue,
        status: "sending",
        recipients_total: recipientsTotal,
        created_by: adminUserId,
        started_at: new Date().toISOString(),
      })
      .select("id")
      .single();
    if (insErr || !row) {
      return json(
        { error: "db_error", detail: insErr?.message },
        500,
      );
    }
    const broadcastId = row.id as string;

    // 3) Procesar primer batch en background sin bloquear la respuesta.
    //    Devolvemos inmediatamente al cliente con el broadcast_id para
    //    que pueda navegar al detail y empezar a pollear progress.
    //    EdgeRuntime.waitUntil mantiene el worker vivo despues de la
    //    respuesta HTTP.
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil?.(
      processBroadcast(admin, broadcastId, supabaseUrl, serviceRoleKey),
    );

    return json(
      {
        ok: true,
        broadcast_id: broadcastId,
        recipients_total: recipientsTotal,
      },
      200,
    );
  }

  // ─────────────────────────── CONTINUE ─────────────────────────
  if (action === "continue") {
    if (!isInternal) return json({ error: "forbidden" }, 403);
    const broadcastId = body.broadcast_id as string | undefined;
    if (!broadcastId) return json({ error: "missing_broadcast_id" }, 400);
    // Procesar (no en background, ya estamos en una invocacion
    // dedicada que no devuelve hasta acabar el batch).
    await processBroadcast(admin, broadcastId, supabaseUrl, serviceRoleKey);
    return json({ ok: true }, 200);
  }

  return json({ error: "unknown_action" }, 400);
}));

// ─────────────────────────────────────────────────────────────────────
// Procesa N batches del broadcast hasta agotar tiempo o audiencia.
// Si queda mas, auto-invoca `continue` para no perder el progreso.
// ─────────────────────────────────────────────────────────────────────
async function processBroadcast(
  // deno-lint-ignore no-explicit-any
  admin: any,
  broadcastId: string,
  supabaseUrl: string,
  serviceRoleKey: string,
): Promise<void> {
  const startedAt = Date.now();
  const appName = await fetchAppName(admin);

  // Loop de batches mientras quede tiempo y audiencia.
  while (Date.now() - startedAt < MAX_FUNCTION_RUNTIME_MS) {
    // 1) Leer estado actual del broadcast.
    const { data: b, error: readErr } = await admin
      .from("broadcasts")
      .select(
        "id, subject, body_html, recipients_total, sent_count, "
          + "failed_count, processed_offset, status",
      )
      .eq("id", broadcastId)
      .maybeSingle();
    if (readErr || !b) {
      await captureError(
        new Error(`broadcast ${broadcastId} not found in processBroadcast`),
      );
      return;
    }
    if (b.status !== "sending") {
      // Ya estaba terminado o pausado, no seguimos.
      return;
    }
    if (b.processed_offset >= b.recipients_total) {
      // Termino — marcamos sent (o failed si hubo > 0 failed).
      await admin
        .from("broadcasts")
        .update({
          status: "sent",
          finished_at: new Date().toISOString(),
        })
        .eq("id", broadcastId);
      return;
    }

    // 2) Obtener siguiente batch de recipients.
    const { data: batch, error: batchErr } = await admin.rpc(
      "admin_broadcast_recipients_batch",
      {
        p_broadcast_id: broadcastId,
        p_offset: b.processed_offset,
        p_limit: 50,
      },
    );
    if (batchErr) {
      await admin
        .from("broadcasts")
        .update({
          status: "failed",
          last_error: `batch_query: ${batchErr.message}`.slice(0, 500),
          finished_at: new Date().toISOString(),
        })
        .eq("id", broadcastId);
      return;
    }
    const recipients = (batch as Array<{
      user_id: string;
      email: string;
      locale: string;
    }>) ?? [];

    if (recipients.length === 0) {
      // No mas recipients — terminar.
      await admin
        .from("broadcasts")
        .update({
          status: "sent",
          finished_at: new Date().toISOString(),
        })
        .eq("id", broadcastId);
      return;
    }

    // 3) Renderizar + enviar cada email del batch en paralelo controlado.
    //    Limit de concurrencia: 5 simultaneos para no saturar SMTP de
    //    Dondominio (hosting compartido sufre con > 10 conexiones a la
    //    vez).
    let batchSent = 0;
    let batchFailed = 0;
    const CONCURRENCY = 5;
    for (let i = 0; i < recipients.length; i += CONCURRENCY) {
      const chunk = recipients.slice(i, i + CONCURRENCY);
      const results = await Promise.all(
        chunk.map(async (r) => {
          const rendered = renderEmail({
            type: "broadcast",
            locale: r.locale,
            appName,
            data: { subject: b.subject, body: b.body_html },
          });
          return sendEmail(admin, {
            type: "broadcast",
            to: r.email,
            toUserId: r.user_id,
            locale: r.locale,
            subject: rendered.subject,
            htmlBody: rendered.htmlBody,
            textBody: rendered.textBody,
            meta: { broadcast_id: broadcastId },
          });
        }),
      );
      for (const r of results) {
        if (r.ok) batchSent++;
        else batchFailed++;
      }
    }

    // 4) Actualizar progreso del broadcast.
    await admin
      .from("broadcasts")
      .update({
        sent_count: (b.sent_count ?? 0) + batchSent,
        failed_count: (b.failed_count ?? 0) + batchFailed,
        processed_offset: (b.processed_offset ?? 0) + recipients.length,
      })
      .eq("id", broadcastId);
  }

  // Si llegamos aqui es porque agotamos tiempo y aun queda audiencia
  // -> auto-invocar continue via fetch.
  fetch(`${supabaseUrl}/functions/v1/broadcast-dispatch`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-internal-auth": serviceRoleKey,
    },
    body: JSON.stringify({ action: "continue", broadcast_id: broadcastId }),
  }).catch((e) => {
    // El fire-and-forget puede fallar (network, etc.) — capturamos
    // pero no podemos hacer mas; el siguiente envio quedara pausado
    // hasta que un admin lo reanude manualmente (boton retry futuro).
    captureError(e, { fn: "broadcast-dispatch-continue-self" });
  });
}
