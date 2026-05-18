// ============================================================================
// Edge Function: scan-upload (PR-C)
// ----------------------------------------------------------------------------
// Escanea un upload con VirusTotal y actualiza
// `uploads.virus_scan_status` + `virus_scan_result`. Si el archivo es
// suspicious (>=1 motor flageo malicious), lo soft-deletea
// automaticamente.
//
// **Quien la invoca**:
//   - `upload-file` action=confirm_upload (fire-and-forget tras
//     confirmacion exitosa de magic bytes / sha256). Header
//     `x-internal-auth: <service_role_key>`.
//   - Admin manual via re-scan boton (no implementado en V1 -- pendiente).
//
// **Body**:
//   { "upload_id": "<uuid>" }
//
// **Flow**:
//   1. Lee la fila upload (paths, sha256, mime, size).
//   2. Si virus_scan_status != 'pending' -> no-op (idempotente).
//   3. Si size > 32 MB -> marca 'skipped' (free tier limite VT).
//   4. Si sha256 es null (legacy upload) -> marca 'skipped'.
//   5. Descarga el archivo del bucket SOLO si necesario (lookup por
//      hash primero, que es free).
//   6. Llama a `scanFileVirusTotal()` helper.
//   7. Actualiza la fila con el resultado.
//   8. Si suspicious: soft-delete + (TODO) notificar al admin via
//      audit_log entry.
//
// **No bloquea al user**: el frontend muestra el upload con chip
// "Escaneando..." mientras esta `pending`. Cuando vuelve, refresca y ve
// el estado final.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry, captureError } from "../_shared/sentry.ts";
import { scanFileVirusTotal } from "../_shared/virustotal.ts";

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

// Free tier limite. Sincronizado con _shared/virustotal.ts.
const VT_MAX_FILE_BYTES = 32 * 1024 * 1024;

Deno.serve(withSentry("scan-upload", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Auth: aceptamos service_role via X-Internal-Auth (uso normal:
  // upload-file invocandonos en fire-and-forget). Tambien podriamos
  // aceptar JWT admin en el futuro para re-scan manual.
  const internalAuth = req.headers.get("X-Internal-Auth");
  if (internalAuth !== serviceRoleKey) {
    return json({ error: "forbidden" }, 403);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const uploadId = body.upload_id as string | undefined;
  if (!uploadId) {
    return json({ error: "missing_upload_id" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // **CAMBIO DE ESTRATEGIA** (hotfix post PR-C):
  // Respondemos 200 INMEDIATO al caller (upload-file) tras una
  // validacion minima del input. El work pesado (descargar object +
  // llamar a VT + actualizar BD) lo hacemos en background via
  // `EdgeRuntime.waitUntil`. Asi:
  //   - upload-file puede hacer `await fetch(scan-upload)` sin
  //     bloquearse 30s esperando el scan completo.
  //   - El gateway no mata el worker porque sigue habiendo promesa
  //     registrada.
  //
  // Si `EdgeRuntime.waitUntil` no existe en este runtime (test local,
  // version vieja), caemos al modo sincrono (await del scan completo
  // antes de responder). Funcional pero lento.

  // deno-lint-ignore no-explicit-any
  const waitUntil = (globalThis as any).EdgeRuntime?.waitUntil?.bind(
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime,
  );

  if (typeof waitUntil === "function") {
    waitUntil(_processScan(admin, uploadId));
    return json({ ok: true, queued: true }, 200);
  } else {
    // Fallback sincrono.
    await _processScan(admin, uploadId);
    return json({ ok: true, queued: false }, 200);
  }
}));

// ─────────────────────────────────────────────────────────────────────
// Toda la logica de scan/update/cleanup encapsulada para que se pueda
// invocar via waitUntil (background) o await (sync fallback).
// ─────────────────────────────────────────────────────────────────────
async function _processScan(
  // deno-lint-ignore no-explicit-any
  admin: any,
  uploadId: string,
): Promise<void> {
  // 1) Leer la fila.
  const { data: row, error: readErr } = await admin
    .from("uploads")
    .select(
      "id, user_id, bucket, path, filename, mime_type, size_bytes, "
        + "sha256, virus_scan_status",
    )
    .eq("id", uploadId)
    .maybeSingle();
  if (readErr || !row) {
    await captureError(
      new Error(`scan-upload: upload not found ${uploadId}`),
      { fn: "scan-upload", stage: "read_row" },
    );
    return;
  }

  // 2) Idempotente.
  if (row.virus_scan_status !== "pending") return;

  // 3) Pre-skips.
  if (!row.sha256) {
    await _markStatus(admin, uploadId, "skipped", {
      reason: "no_sha256",
      note: "Upload legacy sin sha256 -- no escaneable.",
    });
    return;
  }
  if ((row.size_bytes as number) > VT_MAX_FILE_BYTES) {
    await _markStatus(admin, uploadId, "skipped", {
      reason: "file_too_large_for_vt_free",
      size_bytes: row.size_bytes,
      max_bytes: VT_MAX_FILE_BYTES,
    });
    return;
  }

  // 4) Descargar bytes (necesarios si VT no conoce el hash).
  let bytes: Uint8Array | null = null;
  try {
    const { data: blob, error: dlErr } = await admin.storage
      .from(row.bucket as string)
      .download(row.path as string);
    if (!dlErr && blob) {
      bytes = new Uint8Array(await blob.arrayBuffer());
    }
  } catch (e) {
    await captureError(
      e instanceof Error ? e : new Error(String(e)),
      { fn: "scan-upload", stage: "download", upload_id: uploadId },
    );
  }

  // 5) Scan via VirusTotal.
  const scanResult = await scanFileVirusTotal({
    sha256: row.sha256 as string,
    bytes,
    filename: row.filename as string,
    mimeType: row.mime_type as string,
  });

  // 6) Update BD.
  await _markStatus(admin, uploadId, scanResult.status, scanResult.result);

  // 7) Si suspicious -> soft-delete + audit_log entry.
  if (scanResult.status === "suspicious") {
    const { error: delErr } = await admin
      .from("uploads")
      .update({ deleted_at: new Date().toISOString() })
      .eq("id", uploadId);
    if (delErr) {
      await captureError(new Error(delErr.message), {
        fn: "scan-upload",
        stage: "soft_delete_suspicious",
        upload_id: uploadId,
      });
    }
    // Insert con el schema real de audit_logs (migracion 0008):
    // (user_id, event, metadata, occurred_at). NO hay actor_id ni
    // target_user_id -- es un log por user. Para "system" eventos como
    // este, usamos el user_id del dueno del upload (mismo target).
    try {
      const { error: auditErr } = await admin.from("audit_logs").insert({
        user_id: row.user_id,
        event: "upload.virus_detected",
        metadata: {
          upload_id: uploadId,
          filename: row.filename,
          mime_type: row.mime_type,
          size_bytes: row.size_bytes,
          sha256: row.sha256,
          scan_summary: scanResult.result,
        },
      });
      if (auditErr) {
        await captureError(new Error(auditErr.message), {
          fn: "scan-upload",
          stage: "audit_log_insert",
          upload_id: uploadId,
        });
      }
    } catch (e) {
      await captureError(
        e instanceof Error ? e : new Error(String(e)),
        { fn: "scan-upload", stage: "audit_log_insert" },
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// Helper: actualiza virus_scan_status/result/at en una fila uploads.
// ─────────────────────────────────────────────────────────────────────
async function _markStatus(
  // deno-lint-ignore no-explicit-any
  admin: any,
  uploadId: string,
  status: string,
  result: Record<string, unknown>,
): Promise<void> {
  const { error } = await admin
    .from("uploads")
    .update({
      virus_scan_status: status,
      virus_scan_result: result,
      virus_scan_at: new Date().toISOString(),
    })
    .eq("id", uploadId);
  if (error) {
    await captureError(new Error(error.message), {
      fn: "scan-upload",
      stage: "mark_status",
      upload_id: uploadId,
      target_status: status,
    });
  }
}
