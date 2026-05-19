// ============================================================================
// Helper compartido: Sentry para Edge Functions (Deno)
// ----------------------------------------------------------------------------
// Lazy-init del SDK de Sentry para Deno. Si la env `SENTRY_DSN` no está
// configurada en el dashboard de Supabase Functions, todas las llamadas
// quedan en no-op silencioso (perfecto para dev local).
//
// Uso típico desde una Edge Function:
//
// ```ts
// import { withSentry, captureError } from "../_shared/sentry.ts";
//
// Deno.serve(withSentry("delete-account", async (req) => {
//   ...
//   try { ... } catch (e) {
//     await captureError(e, { request: req, fn: "delete-account" });
//     throw e;
//   }
// }));
// ```
// ============================================================================

import * as Sentry from "https://deno.land/x/sentry@8.40.0/index.mjs";

let initialized = false;

function initOnce() {
  if (initialized) return;
  initialized = true;
  const dsn = Deno.env.get("SENTRY_DSN");
  if (!dsn) return;
  Sentry.init({
    dsn,
    environment: Deno.env.get("APP_ENV") ?? "prod",
    release: Deno.env.get("APP_VERSION") ?? undefined,
    tracesSampleRate: 0.1,
    sendDefaultPii: false,
  });
}

/**
 * Captura una excepción con contexto enriquecido. Safe no-op si no hay DSN.
 *
 * `extra` se serializa como contexto en Sentry para que veas en el evento
 * qué función falló, qué payload llegó, etc.
 */
export async function captureError(
  err: unknown,
  extra: Record<string, unknown> = {},
): Promise<void> {
  initOnce();
  if (!Deno.env.get("SENTRY_DSN")) return;
  try {
    Sentry.withScope((scope) => {
      for (const [k, v] of Object.entries(extra)) {
        scope.setExtra(k, v);
      }
      Sentry.captureException(err);
    });
    await Sentry.flush(2000);
  } catch (_) {
    // Nunca queremos que el reporting a Sentry rompa la respuesta de la
    // edge function. Si Sentry falla, lo log y seguimos.
    console.error("Sentry capture failed:", _);
  }
}

/**
 * Captura un mensaje sin excepcion asociada. Util para "alerts" donde
 * no hay un error pero queremos que el admin reciba notificacion (ej.
 * audits que detectan findings critical).
 *
 * `level` mapea a la severity en Sentry: 'fatal' | 'error' | 'warning'
 * | 'info' | 'debug'. Por defecto 'warning' -- "no es un crash, pero
 * mira esto".
 *
 * Safe no-op si no hay DSN.
 */
export async function captureMessage(
  message: string,
  level: "fatal" | "error" | "warning" | "info" | "debug" = "warning",
  extra: Record<string, unknown> = {},
): Promise<void> {
  initOnce();
  if (!Deno.env.get("SENTRY_DSN")) return;
  try {
    Sentry.withScope((scope) => {
      scope.setLevel(level);
      for (const [k, v] of Object.entries(extra)) {
        scope.setExtra(k, v);
      }
      Sentry.captureMessage(message);
    });
    await Sentry.flush(2000);
  } catch (_) {
    console.error("Sentry message capture failed:", _);
  }
}

/**
 * Wrapper para envolver un handler de `Deno.serve(...)` y reportar
 * automáticamente cualquier excepción que escape. La response sigue
 * siendo responsabilidad del handler.
 *
 * Adjunta un `correlation_id` único por request en la respuesta como
 * cabecera `x-request-id` para correlacionar logs del cliente con logs
 * del backend.
 */
export function withSentry(
  fnName: string,
  handler: (req: Request) => Promise<Response>,
): (req: Request) => Promise<Response> {
  initOnce();
  return async (req: Request): Promise<Response> => {
    const requestId = crypto.randomUUID();
    try {
      const res = await handler(req);
      // Añadimos el request-id a la respuesta sin tocar el body.
      const headers = new Headers(res.headers);
      if (!headers.has("x-request-id")) {
        headers.set("x-request-id", requestId);
      }
      return new Response(res.body, {
        status: res.status,
        statusText: res.statusText,
        headers,
      });
    } catch (e) {
      await captureError(e, {
        fn: fnName,
        request_id: requestId,
        method: req.method,
        url: req.url,
      });
      console.error(`[${fnName}] uncaught:`, e);
      return new Response(
        JSON.stringify({ error: "internal_error", request_id: requestId }),
        {
          status: 500,
          headers: {
            "content-type": "application/json",
            "x-request-id": requestId,
          },
        },
      );
    }
  };
}
