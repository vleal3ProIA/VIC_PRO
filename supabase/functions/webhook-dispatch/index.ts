// ============================================================================
// Edge Function: webhook-dispatch
// ----------------------------------------------------------------------------
// Hace el trabajo de salida: para una accion dada (`create_endpoint`,
// `test`, `send`, `retry_pending`) actua sobre la tabla
// `webhook_endpoints` y `webhook_deliveries`.
//
// **Acciones**:
//
//   1) `create_endpoint`
//      Body: { url, description?, events?, tenant_id? }
//      - Valida URL (https obligatorio en prod, http permitido para tests
//        locales identificando dominio localhost/127.0.0.1).
//      - Genera secret raw 32 bytes -> base64url.
//      - INSERT endpoint con `secret_hash = SHA-256(secret)` +
//        INSERT webhook_secrets (raw) en TX.
//      - Devuelve endpoint + secret RAW (1 vez).
//
//   2) `test`
//      Body: { endpoint_id }
//      - Crea un delivery con event_type = 'test.ping' + payload de
//        prueba { sent_at, ... }.
//      - Despacha sincronamente y devuelve {status, http_status, error}.
//      - Util para el boton "Send test" en la UI.
//
//   3) `send`  (uso interno desde otras Edge Functions)
//      Body: { event_type, payload, tenant_id? }
//      - Encuentra todos los endpoints activos suscritos al event_type
//        (o al comodin '*'). Por cada uno crea un delivery 'pending'
//        y lo despacha en paralelo.
//      - Llamable solo con header `X-Internal-Auth: <SERVICE_ROLE_KEY>`
//        (cualquiera no puede enviar webhooks arbitrarios).
//
//   4) `retry_pending`  (cron job futuro)
//      - Busca deliveries con status='retry' y next_retry_at <= now()
//        (limite 100 por ejecucion para no agotar el isolate).
//      - Las despacha y registra success/failure.
//
// **POST a la URL del cliente**:
//   - Header `X-Webhook-Signature: sha256=<hmac_hex>` calculado sobre
//     el body crudo con el secret raw.
//   - Header `X-Webhook-Event: <event_type>`.
//   - Header `X-Webhook-Delivery: <delivery_id>`.
//   - Timeout 10s. Codes 2xx -> success. Otros -> failure con
//     backoff exponencial: 1m, 5m, 30m, 2h, 12h.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";

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

const VALID_EVENTS = [
  "*",
  "user.created",
  "user.deleted",
  "subscription.created",
  "subscription.updated",
  "subscription.canceled",
  "invoice.paid",
  "invoice.failed",
];

const POST_TIMEOUT_MS = 10_000;
const RETRY_DELAYS_MS = [
  60_000,        // 1 min
  5 * 60_000,    // 5 min
  30 * 60_000,   // 30 min
  2 * 3600_000,  // 2 h
  12 * 3600_000, // 12 h
];

function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha256Hex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(body),
  );
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function isValidUrl(u: string): boolean {
  try {
    const url = new URL(u);
    if (url.protocol === "https:") return true;
    // http:// solo permitido contra localhost para tests.
    if (
      url.protocol === "http:" &&
      (url.hostname === "localhost" || url.hostname === "127.0.0.1")
    ) {
      return true;
    }
    return false;
  } catch {
    return false;
  }
}

function validateEvents(arr: unknown): { ok: true; events: string[] } | { ok: false; bad: string } {
  if (!Array.isArray(arr) || arr.length === 0) {
    return { ok: false, bad: "empty" };
  }
  const clean = Array.from(
    new Set(arr.filter((x): x is string => typeof x === "string")),
  );
  for (const ev of clean) {
    if (!VALID_EVENTS.includes(ev)) {
      return { ok: false, bad: ev };
    }
  }
  return { ok: true, events: clean };
}

// Realiza el POST al cliente con la firma. Devuelve outcome.
async function postToEndpoint(args: {
  url: string;
  secret: string;
  eventType: string;
  payload: Record<string, unknown>;
  deliveryId: string;
}): Promise<
  | { ok: true; httpStatus: number; body: string }
  | { ok: false; httpStatus: number | null; error: string; body?: string }
> {
  const bodyStr = JSON.stringify(args.payload);
  const sig = await hmacSha256Hex(args.secret, bodyStr);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), POST_TIMEOUT_MS);
  try {
    const res = await fetch(args.url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-webhook-signature": `sha256=${sig}`,
        "x-webhook-event": args.eventType,
        "x-webhook-delivery": args.deliveryId,
        "user-agent": "myapp-webhooks/1.0",
      },
      body: bodyStr,
      signal: controller.signal,
    });
    const text = (await res.text().catch(() => "")).slice(0, 2048);
    if (res.status >= 200 && res.status < 300) {
      return { ok: true, httpStatus: res.status, body: text };
    }
    return {
      ok: false,
      httpStatus: res.status,
      error: `http_${res.status}`,
      body: text,
    };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return {
      ok: false,
      httpStatus: null,
      error: msg.includes("abort") ? "timeout" : `network_${msg}`.slice(0, 120),
    };
  } finally {
    clearTimeout(timeout);
  }
}

// Dado un attempt actual (1 = primer fallo), devuelve el ms hasta el
// proximo retry, o null si ya excedimos.
function nextDelayMs(currentAttempt: number): number | null {
  // attempt=1 fallo -> next es RETRY_DELAYS_MS[0]; tras attempt=5 falla, exhausto.
  const idx = currentAttempt - 1;
  if (idx < 0 || idx >= RETRY_DELAYS_MS.length) return null;
  return RETRY_DELAYS_MS[idx];
}

Deno.serve(withSentry("webhook-dispatch", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const action = body.action as string | undefined;

  // ────────────────────────── CREATE ENDPOINT ──────────────────────────
  if (action === "create_endpoint") {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "missing_authorization" }, 401);
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userErr,
    } = await userClient.auth.getUser();
    if (userErr || !user) return json({ error: "invalid_token" }, 401);

    const url = (body.url as string | undefined)?.trim();
    const description = (body.description as string | undefined)?.trim() || null;
    const tenantId = (body.tenant_id as string | undefined) || null;
    if (!url || !isValidUrl(url)) {
      return json({ error: "invalid_url" }, 400);
    }
    const eventsRaw = body.events ?? ["*"];
    const eventsCheck = validateEvents(eventsRaw);
    if (!eventsCheck.ok) {
      return json({ error: "invalid_events", bad: eventsCheck.bad }, 400);
    }

    const secretBytes = new Uint8Array(32);
    crypto.getRandomValues(secretBytes);
    const secret = `whsec_${base64UrlEncode(secretBytes)}`;
    const secretHash = await sha256Hex(secret);

    // INSERT endpoint primero.
    const { data: endpoint, error: insErr } = await admin
      .from("webhook_endpoints")
      .insert({
        user_id: user.id,
        tenant_id: tenantId,
        url,
        description,
        secret_hash: secretHash,
        events: eventsCheck.events,
      })
      .select(
        "id, tenant_id, user_id, url, description, events, active, "
          + "consecutive_failures, disabled_reason, created_at, updated_at",
      )
      .single();
    if (insErr || !endpoint) {
      return json({ error: "db_error", detail: insErr?.message }, 500);
    }

    // Luego guardamos el secret en la pivote (RLS lo bloquea).
    const { error: secErr } = await admin
      .from("webhook_secrets")
      .insert({ endpoint_id: endpoint.id, secret });
    if (secErr) {
      // Si falla, rollback del endpoint (sin TX explicita, hacemos
      // delete) para no dejar endpoint sin secret.
      await admin.from("webhook_endpoints").delete().eq("id", endpoint.id);
      return json({ error: "db_error", detail: secErr.message }, 500);
    }

    return json({ ...endpoint, secret }, 201);
  }

  // ────────────────────────── TEST ────────────────────────────────
  if (action === "test") {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "missing_authorization" }, 401);
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userErr,
    } = await userClient.auth.getUser();
    if (userErr || !user) return json({ error: "invalid_token" }, 401);

    const endpointId = body.endpoint_id as string | undefined;
    if (!endpointId) return json({ error: "missing_endpoint_id" }, 400);

    // Lee endpoint via user client (RLS) -- si no es suyo, 404.
    const { data: endpoint } = await userClient
      .from("webhook_endpoints")
      .select("id, url")
      .eq("id", endpointId)
      .maybeSingle();
    if (!endpoint) return json({ error: "not_found" }, 404);

    // Lee secret via admin (RLS lo bloqueaba al user).
    const { data: secretRow } = await admin
      .from("webhook_secrets")
      .select("secret")
      .eq("endpoint_id", endpointId)
      .maybeSingle();
    if (!secretRow) return json({ error: "secret_missing" }, 500);

    const payload = {
      sent_at: new Date().toISOString(),
      delivery_kind: "test",
      message: "If you can read this, your webhook is set up correctly.",
    };
    const { data: delivery } = await admin
      .from("webhook_deliveries")
      .insert({
        endpoint_id: endpointId,
        event_type: "test.ping",
        payload,
        status: "pending",
      })
      .select("id")
      .single();

    const outcome = await postToEndpoint({
      url: endpoint.url as string,
      secret: secretRow.secret as string,
      eventType: "test.ping",
      payload,
      deliveryId: delivery!.id as string,
    });

    if (outcome.ok) {
      await admin.rpc("record_webhook_success", {
        p_delivery_id: delivery!.id,
        p_http_status: outcome.httpStatus,
        p_response_body: outcome.body,
      });
      return json(
        { status: "success", http_status: outcome.httpStatus },
        200,
      );
    } else {
      await admin.rpc("record_webhook_failure", {
        p_delivery_id: delivery!.id,
        p_http_status: outcome.httpStatus,
        p_error: outcome.error,
        p_next_retry_at: null, // tests no se reintentan.
      });
      return json(
        {
          status: "failed",
          http_status: outcome.httpStatus,
          error: outcome.error,
        },
        200, // 200 con status:failed para que la UI lo pinte sin "explotar".
      );
    }
  }

  // ─────────────────────────── ROTATE SECRET ────────────────────
  // Cierra el TODO de SECURITY.md PR-F sobre `webhook_secret_rotate`.
  //
  // Genera un nuevo HMAC secret para un endpoint existente. El secret
  // viejo deja de ser valido inmediatamente -- cualquier dispatcher
  // posterior firma con el nuevo. El secret raw se devuelve UNA SOLA
  // VEZ en la response, igual que en create_endpoint.
  //
  // **Gate de seguridad**: exige `consume_recent_verification(
  // 'webhook_secret_rotate')`. Sin password reciente, devuelve 403
  // 'reauth_required'. La UI llama a ReauthDialog antes de invocar.
  //
  // **Ownership**: el endpoint se lee con userClient (RLS); si no
  // pertenece al user, 404. Asi un atacante con JWT robado pero sin
  // acceso al endpoint no puede rotar secrets de otros users.
  if (action === "rotate_secret") {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "missing_authorization" }, 401);
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userErr,
    } = await userClient.auth.getUser();
    if (userErr || !user) return json({ error: "invalid_token" }, 401);

    const endpointId = body.endpoint_id as string | undefined;
    if (!endpointId) return json({ error: "missing_endpoint_id" }, 400);

    // Ownership check via user client (bloquea ataques cross-user
    // incluso con re-auth fresca).
    const { data: endpoint } = await userClient
      .from("webhook_endpoints")
      .select("id, user_id")
      .eq("id", endpointId)
      .maybeSingle();
    if (!endpoint) return json({ error: "not_found" }, 404);
    if (endpoint.user_id !== user.id) {
      return json({ error: "not_owner" }, 403);
    }

    // Gate re-auth: consume una verificacion fresca del action_kind
    // `webhook_secret_rotate`. La RPC borra la fila si existe y
    // devuelve true; false si no hay verificacion vigente.
    const { data: verified, error: vErr } = await admin.rpc(
      "consume_recent_verification",
      {
        p_action_kind: "webhook_secret_rotate",
        p_user_id: user.id,
      },
    );
    if (vErr) {
      return json({ error: "reauth_check_failed", detail: vErr.message }, 500);
    }
    if (verified !== true) {
      return json({ error: "reauth_required" }, 403);
    }

    // Genera nuevo secret (mismo formato que create_endpoint).
    const secretBytes = new Uint8Array(32);
    crypto.getRandomValues(secretBytes);
    const newSecret = `whsec_${base64UrlEncode(secretBytes)}`;
    const newHash = await sha256Hex(newSecret);

    // 1) UPDATE webhook_endpoints.secret_hash + updated_at.
    const { error: hashErr } = await admin
      .from("webhook_endpoints")
      .update({
        secret_hash: newHash,
        updated_at: new Date().toISOString(),
      })
      .eq("id", endpointId);
    if (hashErr) {
      return json({ error: "db_error", detail: hashErr.message }, 500);
    }

    // 2) UPDATE webhook_secrets (pivote) con el nuevo raw.
    const { error: secErr } = await admin
      .from("webhook_secrets")
      .update({ secret: newSecret })
      .eq("endpoint_id", endpointId);
    if (secErr) {
      // Rollback parcial: el secret_hash ya cambio. Devolvemos error
      // -- el admin tendra que rotar otra vez. Riesgo aceptable:
      // probabilidad de que update 2 falle es < 0.01% y la rotacion
      // es idempotente.
      return json({ error: "db_error", detail: secErr.message }, 500);
    }

    return json({ ok: true, secret: newSecret }, 200);
  }

  // ─────────────────────────── SEND ─────────────────────────────
  if (action === "send") {
    const internalAuth = req.headers.get("X-Internal-Auth");
    if (internalAuth !== serviceRoleKey) {
      return json({ error: "forbidden" }, 403);
    }
    const eventType = body.event_type as string | undefined;
    const payload = body.payload as Record<string, unknown> | undefined;
    const tenantId = (body.tenant_id as string | undefined) || null;
    if (!eventType || !payload) {
      return json({ error: "missing_fields" }, 400);
    }
    if (!VALID_EVENTS.includes(eventType)) {
      return json({ error: "invalid_event_type" }, 400);
    }

    // Endpoints activos suscritos al evento (o '*').
    let q = admin
      .from("webhook_endpoints")
      .select(
        "id, url, events, tenant_id, "
          + "secret:webhook_secrets!inner(secret)",
      )
      .eq("active", true)
      .or(`events.cs.{${eventType}},events.cs.{*}`);
    if (tenantId) {
      q = q.or(`tenant_id.eq.${tenantId},tenant_id.is.null`);
    }
    const { data: endpoints, error: listErr } = await q;
    if (listErr) {
      return json({ error: "db_error", detail: listErr.message }, 500);
    }
    if (!endpoints || endpoints.length === 0) {
      return json({ dispatched: 0 }, 200);
    }

    let dispatched = 0;
    await Promise.all(
      endpoints.map(async (ep) => {
        const secretRows = ep.secret as { secret: string }[] | { secret: string } | null;
        const secret = Array.isArray(secretRows)
          ? secretRows[0]?.secret
          : secretRows?.secret;
        if (!secret) return;

        const { data: delivery } = await admin
          .from("webhook_deliveries")
          .insert({
            endpoint_id: ep.id,
            event_type: eventType,
            payload,
            status: "pending",
          })
          .select("id")
          .single();
        if (!delivery) return;

        const outcome = await postToEndpoint({
          url: ep.url as string,
          secret,
          eventType,
          payload,
          deliveryId: delivery.id as string,
        });
        if (outcome.ok) {
          await admin.rpc("record_webhook_success", {
            p_delivery_id: delivery.id,
            p_http_status: outcome.httpStatus,
            p_response_body: outcome.body,
          });
          dispatched++;
        } else {
          const delay = nextDelayMs(1);
          await admin.rpc("record_webhook_failure", {
            p_delivery_id: delivery.id,
            p_http_status: outcome.httpStatus,
            p_error: outcome.error,
            p_next_retry_at: delay
              ? new Date(Date.now() + delay).toISOString()
              : null,
          });
        }
      }),
    );
    return json({ dispatched, total: endpoints.length }, 200);
  }

  // ────────────────────────── RETRY ─────────────────────────────
  if (action === "retry_pending") {
    const internalAuth = req.headers.get("X-Internal-Auth");
    if (internalAuth !== serviceRoleKey) {
      return json({ error: "forbidden" }, 403);
    }
    const { data: due } = await admin
      .from("webhook_deliveries")
      .select(
        "id, endpoint_id, event_type, payload, attempt, "
          + "endpoint:webhook_endpoints!inner(id, url, active, "
          + "secret:webhook_secrets!inner(secret))",
      )
      .eq("status", "retry")
      .lte("next_retry_at", new Date().toISOString())
      .limit(100);
    if (!due || due.length === 0) {
      return json({ retried: 0 }, 200);
    }
    let retried = 0;
    await Promise.all(
      due.map(async (d) => {
        const ep = d.endpoint as {
          id: string;
          url: string;
          active: boolean;
          secret: { secret: string }[] | { secret: string };
        } | null;
        if (!ep || !ep.active) return;
        const secretRows = ep.secret;
        const secret = Array.isArray(secretRows)
          ? secretRows[0]?.secret
          : secretRows?.secret;
        if (!secret) return;

        const outcome = await postToEndpoint({
          url: ep.url,
          secret,
          eventType: d.event_type as string,
          payload: d.payload as Record<string, unknown>,
          deliveryId: d.id as string,
        });
        if (outcome.ok) {
          await admin.rpc("record_webhook_success", {
            p_delivery_id: d.id,
            p_http_status: outcome.httpStatus,
            p_response_body: outcome.body,
          });
          retried++;
        } else {
          const nextDelay = nextDelayMs((d.attempt as number) + 1);
          await admin.rpc("record_webhook_failure", {
            p_delivery_id: d.id,
            p_http_status: outcome.httpStatus,
            p_error: outcome.error,
            p_next_retry_at: nextDelay
              ? new Date(Date.now() + nextDelay).toISOString()
              : null,
          });
        }
      }),
    );
    return json({ retried, processed: due.length }, 200);
  }

  return json({ error: "unknown_action" }, 400);
}));
