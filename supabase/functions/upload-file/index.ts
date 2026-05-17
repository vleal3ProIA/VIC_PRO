// ============================================================================
// Edge Function: upload-file
// ----------------------------------------------------------------------------
// Endpoint generico para subir un archivo a Supabase Storage con
// validacion de cuota y mime antes de tocar el bucket. Lo invocan
// CUALQUIER feature de la app que necesite subir archivos: avatares
// custom, adjuntos en comentarios, imports CSV, logos de tenant, lo
// que sea.
//
// Flujo:
//   1. Valida JWT + extrae user.id.
//   2. Lee body: { tenant_id, filename, mime_type, data_base64 }.
//   3. Decodifica base64 -> bytes; calcula size.
//   4. Chequea size <= 25 MB (limite duro del bucket).
//   5. Chequea mime contra whitelist.
//   6. Chequea cuota del tenant via RPC get_tenant_storage_quota +
//      get_tenant_storage_usage. Si usage + size > quota -> rechaza.
//   7. Genera path unico `<tenant_id>/<user_id>/<uuid>-<filename>`.
//   8. Uploadea a Storage con service_role.
//   9. Inserta fila en `public.uploads`.
//  10. Devuelve { upload_id, path, signed_url } al cliente.
//
// El signed_url tiene TTL de 1 hora -- suficiente para que la UI
// muestre el archivo recien subido. Si el caller quiere mostrarlo mas
// tarde, llama de nuevo a la funcion con action=get_signed_url.
//
// Body:
//   {
//     "action": "upload",
//     "tenant_id": "<uuid>",      // null = upload personal (no atado a tenant)
//     "filename": "logo.png",
//     "mime_type": "image/png",
//     "data_base64": "iVBORw0KGgo..."
//   }
//
// Otras acciones:
//   { "action": "get_signed_url", "upload_id": "<uuid>" }
//     -> { signed_url } (TTL 1h).
//
//   { "action": "delete", "upload_id": "<uuid>" }
//     -> soft delete (marca deleted_at). El object de Storage se
//        purga en un cron job futuro tras 30 dias.
//
//   { "action": "quota", "tenant_id": "<uuid>" }
//     -> { used_bytes, quota_bytes }  para mostrar barra de uso en UI.
//
// Seguridad: JWT obligatorio. Rate limit 60/h/user (uploads).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";

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
const MAX_FILE_BYTES = 25 * 1024 * 1024; // 25 MB hard limit por file.
const ALLOWED_MIMES = new Set([
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "image/svg+xml",
  "application/pdf",
  "text/csv",
  "text/plain",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/zip",
]);
const SIGNED_URL_TTL = 3600; // 1 hora.

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
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `uploads:user:${user.id}`,
    limit: 60,
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

  // ─────────────────────────────── UPLOAD ────────────────────────────────

  if (action === "upload") {
    const tenantId = body.tenant_id as string | undefined;
    const filename = (body.filename as string | undefined)?.trim();
    const mimeType = body.mime_type as string | undefined;
    const base64 = body.data_base64 as string | undefined;

    if (!filename || !mimeType || !base64) {
      return json({ error: "missing_fields" }, 400);
    }
    if (!ALLOWED_MIMES.has(mimeType)) {
      return json({ error: "unsupported_mime", mime: mimeType }, 400);
    }

    let bytes: Uint8Array;
    try {
      bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    } catch {
      return json({ error: "invalid_base64" }, 400);
    }
    if (bytes.byteLength > MAX_FILE_BYTES) {
      return json(
        { error: "file_too_large", max_bytes: MAX_FILE_BYTES },
        413,
      );
    }

    // Chequeo de cuota — solo si el upload se atribuye a un tenant.
    if (tenantId) {
      const [{ data: usage }, { data: quota }] = await Promise.all([
        admin.rpc("get_tenant_storage_usage", { p_tenant_id: tenantId }),
        admin.rpc("get_tenant_storage_quota", { p_tenant_id: tenantId }),
      ]);
      const quotaNum = Number(quota ?? 0);
      const usageNum = Number(usage ?? 0);
      // quota_bytes = -1 = ilimitado (plan enterprise).
      if (quotaNum >= 0 && usageNum + bytes.byteLength > quotaNum) {
        return json(
          {
            error: "quota_exceeded",
            used_bytes: usageNum,
            quota_bytes: quotaNum,
            file_bytes: bytes.byteLength,
          },
          413,
        );
      }
    }

    // Generar path unico: <tenant_id || 'personal'>/<user_id>/<uuid>-<filename>.
    // Sanitizar filename: solo permitir alfanumerico + . - _ para evitar
    // ataques de path traversal.
    const safeName = filename.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 100);
    const uuid = crypto.randomUUID();
    const folder = tenantId ?? "personal";
    const path = `${folder}/${user.id}/${uuid}-${safeName}`;

    // Subir al bucket con service_role (bypass de policies).
    const { error: uploadErr } = await admin.storage
      .from(BUCKET)
      .upload(path, bytes, {
        contentType: mimeType,
        upsert: false,
      });
    if (uploadErr) {
      return json(
        { error: "storage_error", detail: uploadErr.message },
        500,
      );
    }

    // Insertar fila maestra.
    const { data: row, error: insErr } = await admin
      .from("uploads")
      .insert({
        user_id: user.id,
        tenant_id: tenantId ?? null,
        bucket: BUCKET,
        path,
        filename,
        mime_type: mimeType,
        size_bytes: bytes.byteLength,
      })
      .select()
      .single();
    if (insErr) {
      // Limpia el object si la insercion fallo.
      await admin.storage.from(BUCKET).remove([path]);
      return json({ error: "db_error", detail: insErr.message }, 500);
    }

    // Signed URL para que el cliente lo muestre / descargue.
    const { data: signed } = await admin.storage
      .from(BUCKET)
      .createSignedUrl(path, SIGNED_URL_TTL);

    return json(
      {
        upload_id: row.id,
        path,
        signed_url: signed?.signedUrl ?? null,
        size_bytes: bytes.byteLength,
        mime_type: mimeType,
        filename,
      },
      200,
    );
  }

  // ──────────────────────────── GET SIGNED URL ──────────────────────────

  if (action === "get_signed_url") {
    const uploadId = body.upload_id as string | undefined;
    if (!uploadId) return json({ error: "missing_upload_id" }, 400);

    // Leer el upload con el user client (RLS). Si no puede verlo, 404.
    const { data: row, error } = await userClient
      .from("uploads")
      .select("path, bucket")
      .eq("id", uploadId)
      .maybeSingle();
    if (error || !row) return json({ error: "not_found" }, 404);

    const { data: signed } = await admin.storage
      .from(row.bucket as string)
      .createSignedUrl(row.path as string, SIGNED_URL_TTL);
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

    // El object de Storage NO se borra ahora -- un cron purgara
    // soft-deleted >30 dias. Esto permite "deshacer borrado".
    return json({ ok: true }, 200);
  }

  return json({ error: "unknown_action" }, 400);
}));
