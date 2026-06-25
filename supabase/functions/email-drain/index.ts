// ============================================================================
// Edge Function: email-drain
// ----------------------------------------------------------------------------
// Drena la cola de emails encolados por `auth-email-hook` y otros (ver M3 /
// migracion 0102). Llama a `processEmailQueue` que:
//   1) Reclama hasta `batch` filas con status='queued' via RPC atomica
//      `claim_queued_emails` (FOR UPDATE SKIP LOCKED).
//   2) Abre UNA conexion SMTP y manda el lote entero reusandola.
//   3) Marca sent/failed con backoff exponencial.
//
// **Trigger**: GitHub Actions schedule cada minuto (workflow
// `.github/workflows/email-drain.yml`). Mismo patron que maintenance-cron
// para mantener consistencia y NO depender de pg_cron extension.
//
// **Seguridad**: requiere header `X-Cron-Secret` con el shared secret
// (env var CRON_SECRET en Supabase Functions + GH secret). Sin esto
// cualquiera podria forzar drains. NO usar JWT del user.
// ============================================================================

import { withSentry, captureError } from "../_shared/sentry.ts";
import { adminClient, processEmailQueue } from "../_shared/email.ts";

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.serve(withSentry("email-drain", async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const cronSecret = req.headers.get("X-Cron-Secret") ?? "";
  const expected = Deno.env.get("CRON_SECRET") ?? "";
  if (!expected || cronSecret !== expected) {
    return json({ error: "unauthorized" }, 401);
  }
  const admin = adminClient();
  try {
    // Procesamos hasta 30 emails por invocacion. Con cron cada minuto =
    // 1800 emails/hora -> mucho mas que el SMTP rate-limit normal.
    const result = await processEmailQueue(admin, 30);
    console.log("[email-drain]", JSON.stringify(result));
    return json(result, 200);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await captureError(
      e instanceof Error ? e : new Error(msg),
      { fn: "email-drain" },
    );
    return json({ error: "drain_failed", message: msg }, 500);
  }
}));
