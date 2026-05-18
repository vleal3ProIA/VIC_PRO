// ============================================================================
// Edge Function: upload-file (PR-A hardening)
// ----------------------------------------------------------------------------
// Upload de archivos a Supabase Storage con TODAS las defensas de seguridad
// que el modelo de amenazas pide (ver SECURITY.md sec.6 PR-A):
//
//   - Whitelist estricta de 27 MIME types (sin HTML, sin SVG, sin
//     ejecutables).
//   - Validacion server-side de **magic bytes** (no confiamos en el
//     content-type declarado por el cliente).
//   - Heuristica UTF-8 para tipos texto.
//   - Limite 50 MB por archivo.
//   - Signed Upload URLs: el cliente sube DIRECTO a Supabase Storage
//     (evita el limite ~6 MB de payload de Edge Functions y permite
//     archivos grandes sin streaming complicado).
//   - SHA-256 del contenido almacenado en BD (para deduplicacion y
//     futuro lookup en VirusTotal -- PR-C).
//   - Rate limit 60 uploads/hora/user (sin cambios respecto a antes).
//
// **Flow en dos pasos**:
//
//   1) `request_upload_url`
//      body: { filename, mime_type, size_bytes, tenant_id? }
//      Valida mime, size, cuota del tenant. Genera path unico.
//      Inserta fila en `uploads` con confirmed_at=null (pending).
//      Devuelve: { upload_id, signed_upload_url, path, token, expires_in }
//
//   2) Cliente sube directo a `signed_upload_url` con PUT.
//
//   3) `confirm_upload`
//      body: { upload_id }
//      Edge function descarga los primeros 64 KB con Range, valida
//      magic bytes, calcula sha256 (sobre todo el contenido --
//      descarga completo solo si <= 50 MB), inserta sha256 +
//      magic_validated=true + confirmed_at=now() en la fila pending.
//      Si falla cualquier check: borra el object + marca soft-deleted.
//      Devuelve: { upload_id, signed_url, size_bytes, mime_type, sha256 }
//
// **Acciones legacy mantenidas**:
//   - `get_signed_url` (TTL 1h para descarga)
//   - `delete`         (soft-delete; cron purga >30 dias)
//   - `quota`          (lectura cuota tenant)
//
// **Filas huerfanas**: si el cliente abandona entre paso 1 y 3, la fila
// queda con confirmed_at=null. RLS la oculta (no aparece en /files).
// Un cron job futuro llama a `purge_pending_uploads()` cada hora.
//
// **Avatar**: NO pasa por aqui. El avatar sube directo al bucket
// `avatars` (publico) con RLS de storage. Ver migracion 0004.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry, captureError } from "../_shared/sentry.ts";
import {
  ALLOWED_MIMES,
  isTextLike,
  sha256Hex,
  validateMagicBytes,
  validateUtf8Text,
} from "../_shared/magic_bytes.ts";

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

const BUCKET = "user-uploads";
const MAX_FILE_BYTES = 50 * 1024 * 1024; // 50 MB.
const MIN_FILE_BYTES = 1;                // rechazar 0-byte uploads.
const SIGNED_DOWNLOAD_URL_TTL = 3600;    // 1 h para descargas.
const SIGNED_UPLOAD_URL_TTL = 600;       // 10 min para subir.

// Cuanto descargamos para validar magic bytes en confirm_upload. 64 KB
// es suficiente para todas las signatures que tenemos (la mas profunda
// es TAR a offset 257). Para tipos texto, validamos UTF-8 sobre los
// primeros 8 KB de este sample.
const MAGIC_BYTES_SAMPLE = 64 * 1024;

Deno.serve(withSentry("upload-file", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

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

  // Rate limit aplicado a TODAS las acciones que mutan (request_upload_url,
  // confirm_upload, delete). Lectura (quota, get_signed_url) no consume.
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const action = body.action as string | undefined;
  const MUTATING_ACTIONS = new Set([
    "request_upload_url",
    "confirm_upload",
    "delete",
  ]);
  if (action && MUTATING_ACTIONS.has(action)) {
    const rateOk = await checkRateLimit(admin, {
      bucketKey: `uploads:user:${user.id}`,
      limit: 60,
      windowSeconds: 3600,
    });
    if (!rateOk) return json({ error: "rate_limited" }, 429);
  }

  // ─────────────────────────────── QUOTA ─────────────────────────────────

  if (action === "quota") {
    const tenantId = body.tenant_id as string | undefined;
    if (!tenantId) return json({ error: "missing_tenant_id" }, 400);
    const [usage, quota] = await Promise.all([
      admin.rpc("get_tenant_storage_usage", { p_tenant_id: tenantId }),
      admin.rpc("get_tenant_storage_quota", { p_tenant_id: tenantId }),
    ]);
    return json(
      {
        used_bytes: Number(usage.data ?? 0),
        quota_bytes: Number(quota.data ?? 0),
      },
      200,
    );
  }

  // ─────────────── REQUEST UPLOAD URL (paso 1 de 2) ─────────────────
  // Reservamos slot en BD (fila pending) y devolvemos signed URL para
  // que el cliente suba directo al bucket. Validamos TODO lo que se
  // pueda saber sin tener los bytes todavia: mime en whitelist, size
  // dentro del limite, cuota del tenant.

  if (action === "request_upload_url") {
    const tenantId = body.tenant_id as string | undefined;
    const filename = (body.filename as string | undefined)?.trim();
    const mimeType = body.mime_type as string | undefined;
    const sizeBytes = (body.size_bytes as number | undefined) ?? 0;

    if (!filename || !mimeType || !sizeBytes) {
      return json({ error: "missing_fields" }, 400);
    }
    if (filename.length > 255) {
      return json({ error: "filename_too_long" }, 400);
    }
    if (!ALLOWED_MIMES.has(mimeType)) {
      return json({ error: "unsupported_mime", mime: mimeType }, 400);
    }
    if (sizeBytes < MIN_FILE_BYTES || sizeBytes > MAX_FILE_BYTES) {
      return json(
        {
          error: sizeBytes > MAX_FILE_BYTES ? "file_too_large" : "file_too_small",
          max_bytes: MAX_FILE_BYTES,
          min_bytes: MIN_FILE_BYTES,
        },
        413,
      );
    }

    // Cuota de tenant -- solo si el upload se atribuye a uno.
    if (tenantId) {
      const [{ data: usage }, { data: quota }] = await Promise.all([
        admin.rpc("get_tenant_storage_usage", { p_tenant_id: tenantId }),
        admin.rpc("get_tenant_storage_quota", { p_tenant_id: tenantId }),
      ]);
      const quotaNum = Number(quota ?? 0);
      const usageNum = Number(usage ?? 0);
      if (quotaNum >= 0 && usageNum + sizeBytes > quotaNum) {
        return json(
          {
            error: "quota_exceeded",
            used_bytes: usageNum,
            quota_bytes: quotaNum,
            file_bytes: sizeBytes,
          },
          413,
        );
      }
    }

    // Path unico. Sanitizamos filename a [a-zA-Z0-9._-] para prevenir
    // path traversal o caracteres problematicos en URLs.
    const safeName = filename.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 100);
    const uuid = crypto.randomUUID();
    const folder = tenantId ?? "personal";
    const path = `${folder}/${user.id}/${uuid}-${safeName}`;

    // Insertar fila pending. confirmed_at=null + RLS la oculta de la
    // lista del cliente hasta que confirm_upload la complete.
    const { data: row, error: insErr } = await admin
      .from("uploads")
      .insert({
        user_id: user.id,
        tenant_id: tenantId ?? null,
        bucket: BUCKET,
        path,
        filename,
        mime_type: mimeType,
        size_bytes: sizeBytes,
        // sha256 = null hasta confirm
        // magic_validated = false (default)
        // confirmed_at = null (default)
      })
      .select("id")
      .single();
    if (insErr || !row) {
      return json(
        { error: "db_error", detail: insErr?.message },
        500,
      );
    }

    // Generar signed upload URL. TTL corto (10 min) -- si el cliente
    // tarda mas, vuelve a pedir.
    const { data: signed, error: sigErr } = await admin.storage
      .from(BUCKET)
      .createSignedUploadUrl(path);
    if (sigErr || !signed) {
      // Limpia la fila pending si no podemos firmar.
      await admin.from("uploads").delete().eq("id", row.id);
      return json(
        { error: "signed_url_error", detail: sigErr?.message },
        500,
      );
    }

    return json(
      {
        upload_id: row.id,
        signed_upload_url: signed.signedUrl,
        token: signed.token,
        path,
        expires_in: SIGNED_UPLOAD_URL_TTL,
      },
      200,
    );
  }

  // ─────────────── CONFIRM UPLOAD (paso 2 de 2) ─────────────────────
  // Cliente nos avisa que termino de subir. Validamos magic bytes,
  // calculamos sha256 y completamos la fila. Si la validacion falla,
  // borramos el object + marcamos soft-deleted la fila.

  if (action === "confirm_upload") {
    const uploadId = body.upload_id as string | undefined;
    if (!uploadId) return json({ error: "missing_upload_id" }, 400);

    // Leer la fila pending. RLS bloquea la SELECT del cliente porque
    // confirmed_at is null, pero el service_role bypassa RLS.
    const { data: row, error: readErr } = await admin
      .from("uploads")
      .select(
        "id, user_id, tenant_id, bucket, path, mime_type, "
          + "size_bytes, confirmed_at",
      )
      .eq("id", uploadId)
      .maybeSingle();
    if (readErr || !row) {
      return json({ error: "not_found" }, 404);
    }
    if (row.user_id !== user.id) {
      // Caller no es dueno -- forbidden silencioso.
      return json({ error: "forbidden" }, 403);
    }
    if (row.confirmed_at) {
      // Idempotente: ya confirmado, devolvemos los datos.
      // PR-B: download:true fuerza Content-Disposition: attachment.
      const { data: signed } = await admin.storage
        .from(row.bucket)
        .createSignedUrl(row.path, SIGNED_DOWNLOAD_URL_TTL, {
          download: true,
        });
      return json(
        {
          upload_id: row.id,
          signed_url: signed?.signedUrl ?? null,
          already_confirmed: true,
        },
        200,
      );
    }

    // Descargar todo el archivo del bucket para validar magic bytes +
    // calcular sha256. NOTA: si el archivo > 5 MB, esto consume tiempo
    // de la Edge Function. Para archivos hasta 50 MB es aceptable
    // (~2-5 s tipicamente). Si llegamos a ver timeouts, optimizamos
    // descargando solo `MAGIC_BYTES_SAMPLE` con Range y aceptando
    // sha256 del cliente (verificable contra el de Storage en
    // background).
    const { data: fileBlob, error: dlErr } = await admin.storage
      .from(BUCKET)
      .download(row.path);
    if (dlErr || !fileBlob) {
      // Object no existe -> cliente no subio nada o lo borraron.
      // Marcamos la fila para purga.
      await admin.from("uploads").delete().eq("id", row.id);
      return json(
        { error: "object_not_found", detail: dlErr?.message },
        404,
      );
    }

    const bytes = new Uint8Array(await fileBlob.arrayBuffer());

    // Verificacion 1: size real vs declarado. Toleramos +/- 1024 bytes
    // para overhead minimo de multipart, etc.
    const actualSize = bytes.byteLength;
    if (Math.abs(actualSize - row.size_bytes) > 1024) {
      await rejectAndCleanup(
        admin,
        row.id,
        row.path,
        BUCKET,
        "size_mismatch",
      );
      return json(
        {
          error: "size_mismatch",
          declared: row.size_bytes,
          actual: actualSize,
        },
        400,
      );
    }
    if (actualSize > MAX_FILE_BYTES) {
      await rejectAndCleanup(
        admin,
        row.id,
        row.path,
        BUCKET,
        "file_too_large",
      );
      return json({ error: "file_too_large" }, 413);
    }

    // Verificacion 2: magic bytes.
    const magicOk = validateMagicBytes(bytes, row.mime_type);
    if (!magicOk) {
      await rejectAndCleanup(
        admin,
        row.id,
        row.path,
        BUCKET,
        "magic_bytes_mismatch",
      );
      return json(
        {
          error: "magic_bytes_mismatch",
          mime_declared: row.mime_type,
        },
        400,
      );
    }

    // Verificacion 3 (text-like): UTF-8 heuristica sobre los primeros
    // 8 KB. validateMagicBytes ya lo hace para text-like, pero
    // explicitamos por claridad y para devolver error distinto.
    if (isTextLike(row.mime_type) && !validateUtf8Text(bytes)) {
      await rejectAndCleanup(
        admin,
        row.id,
        row.path,
        BUCKET,
        "invalid_utf8_text",
      );
      return json({ error: "invalid_utf8_text" }, 400);
    }

    // Hash + actualizar fila.
    const hash = await sha256Hex(bytes);

    const { error: updErr } = await admin
      .from("uploads")
      .update({
        sha256: hash,
        magic_validated: true,
        confirmed_at: new Date().toISOString(),
        size_bytes: actualSize, // usar el size real, no el declarado.
      })
      .eq("id", row.id);
    if (updErr) {
      // Update fallo -- mantenemos object pero NO marcamos confirmado.
      // El cron de pending lo purgara tras 1h.
      await captureError(updErr, {
        fn: "upload-file",
        stage: "confirm_update",
      });
      return json({ error: "db_error", detail: updErr.message }, 500);
    }

    // **PR-C**: fire-and-forget scan antivirus. No bloqueamos la
    // respuesta -- el cliente ve el upload con `virus_scan_status='pending'`
    // (RLS no oculta por esto; el chip en UI muestra "Escaneando..."),
    // y cuando `scan-upload` termine actualizara a 'clean' o
    // 'suspicious'. Si VT detecta malware, scan-upload soft-deletea
    // el upload (deleted_at = now()) y la RLS de SELECT (que filtra
    // por `deleted_at IS NULL`) lo oculta automaticamente.
    //
    // Llamamos via fetch con X-Internal-Auth en lugar de
    // admin.functions.invoke porque queremos NO esperar a la respuesta
    // -- el .catch() captura errores de red sin bloquear el return.
    fetch(`${supabaseUrl}/functions/v1/scan-upload`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-internal-auth": serviceRoleKey,
      },
      body: JSON.stringify({ upload_id: row.id }),
    }).catch((e) => {
      captureError(e instanceof Error ? e : new Error(String(e)), {
        fn: "upload-file",
        stage: "scan_upload_invoke",
        upload_id: row.id,
      });
    });

    // Signed URL para descarga. PR-B: download:true fuerza
    // Content-Disposition: attachment para que cualquier archivo
    // (incluyendo los que se cuelen por bugs futuros del whitelist)
    // se descargue en vez de renderizarse inline.
    const { data: signed } = await admin.storage
      .from(BUCKET)
      .createSignedUrl(row.path, SIGNED_DOWNLOAD_URL_TTL, {
        download: true,
      });

    return json(
      {
        upload_id: row.id,
        signed_url: signed?.signedUrl ?? null,
        size_bytes: actualSize,
        mime_type: row.mime_type,
        sha256: hash,
      },
      200,
    );
  }

  // ──────────────────────────── GET SIGNED URL ──────────────────────────

  if (action === "get_signed_url") {
    const uploadId = body.upload_id as string | undefined;
    if (!uploadId) return json({ error: "missing_upload_id" }, 400);

    // userClient + RLS: si no puede verlo (no es propio, no es de su
    // tenant, o no esta confirmado), 404.
    const { data: row, error } = await userClient
      .from("uploads")
      .select("path, bucket")
      .eq("id", uploadId)
      .maybeSingle();
    if (error || !row) return json({ error: "not_found" }, 404);

    // Forzar Content-Disposition: attachment con el query param
    // `download` de Supabase Storage. Defense-in-depth: aunque el
    // whitelist ya excluye HTML/SVG, si por algun bug se cuela un
    // archivo peligroso, no se renderizara inline -- se descargara.
    const { data: signed } = await admin.storage
      .from(row.bucket as string)
      .createSignedUrl(row.path as string, SIGNED_DOWNLOAD_URL_TTL, {
        download: true,
      });
    return json({ signed_url: signed?.signedUrl ?? null }, 200);
  }

  // ─────────────────────────────── DELETE ────────────────────────────────

  if (action === "delete") {
    const uploadId = body.upload_id as string | undefined;
    if (!uploadId) return json({ error: "missing_upload_id" }, 400);

    // Soft delete -- RLS limita a propias.
    const { error } = await userClient
      .from("uploads")
      .update({ deleted_at: new Date().toISOString() })
      .eq("id", uploadId);
    if (error) return json({ error: "db_error", detail: error.message }, 500);

    return json({ ok: true }, 200);
  }

  return json({ error: "unknown_action" }, 400);
}));

// ─────────────────────────────────────────────────────────────────────
// Helper: rechazar un upload pendiente -> borrar object + fila.
// ─────────────────────────────────────────────────────────────────────
async function rejectAndCleanup(
  // deno-lint-ignore no-explicit-any
  admin: any,
  uploadId: string,
  path: string,
  bucket: string,
  reason: string,
): Promise<void> {
  // Borrar object (mejor esfuerzo).
  try {
    await admin.storage.from(bucket).remove([path]);
  } catch (e) {
    await captureError(e instanceof Error ? e : new Error(String(e)), {
      fn: "upload-file",
      stage: "cleanup_storage",
      upload_id: uploadId,
    });
  }
  // Borrar fila pending. No marcamos deleted_at porque la fila nunca
  // llego a ser legitima.
  try {
    await admin.from("uploads").delete().eq("id", uploadId);
  } catch (e) {
    await captureError(e instanceof Error ? e : new Error(String(e)), {
      fn: "upload-file",
      stage: "cleanup_db",
      upload_id: uploadId,
      reason,
    });
  }
}
