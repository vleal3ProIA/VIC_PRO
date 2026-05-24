// ============================================================================
// Edge Function: ingest-document · Ingesta de un documento de un temario (Fase 1)
// ----------------------------------------------------------------------------
// Descarga el archivo subido al bucket `temarios`, lo manda al modelo por
// VISIÓN NATIVA a través del gateway (Gemini -> Claude fallback) y guarda el
// `extracted_text` + idioma detectado, marcando el documento `ready`/`failed`.
//
// Flow (mismo patrón que run-audit):
//   1. Auth del propietario (JWT). El documento debe ser suyo.
//   2. Rate limit.
//   3. status='processing' -> responde 202 inmediato.
//   4. Procesa en background (EdgeRuntime.waitUntil); la UI hace polling.
//
// Tipos soportados: PDF, imagen (image/*) y texto (text/*). DOCX se convierte
// a texto/PDF en el cliente antes de subir (fase posterior).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { captureError, withSentry } from "../_shared/sentry.ts";
import { AiGatewayError, runCompletion } from "../_shared/ai/gateway.ts";
import { extractText, getDocumentProxy } from "https://esm.sh/unpdf@0.12.1";

/// Extrae el texto COMPLETO de un PDF con capa de texto (sin IA, sin truncado).
/// Devuelve "" si no hay texto (PDF escaneado) o si falla.
async function extractPdfText(bytes: Uint8Array): Promise<string> {
  try {
    const pdf = await getDocumentProxy(bytes);
    const res = await extractText(pdf, { mergePages: true });
    const t = (res as { text: unknown }).text;
    if (typeof t === "string") return t;
    if (Array.isArray(t)) return t.join("\n\n");
    return "";
  } catch (_) {
    return "";
  }
}

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

const isSupported = (mime: string): boolean =>
  mime === "application/pdf" ||
  mime.startsWith("image/") ||
  mime.startsWith("text/");

/// base64 sin dependencias externas (chunked para no reventar el stack).
function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/// Extrae el JSON {language,title,text} de la respuesta del modelo, tolerando
/// fences ```json y texto alrededor. Si falla, usa todo el texto como cuerpo.
function parseIngestJson(
  text: string,
): { language?: string; title?: string; text?: string } {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    return JSON.parse(t) as { language?: string; title?: string; text?: string };
  } catch {
    return { text };
  }
}

interface DocumentRow {
  id: string;
  subject_id: string;
  user_id: string;
  storage_path: string;
  mime_type: string | null;
}

Deno.serve(withSentry("ingest-document", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // ─── Auth ───
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey);

  const body = await req.json().catch(() => null) as
    | Record<string, unknown>
    | null;
  const documentId = body?.document_id;
  if (typeof documentId !== "string") {
    return json({ error: "missing_document_id" }, 400);
  }

  const { data: doc, error: docErr } = await admin
    .from("documents")
    .select("id, subject_id, user_id, storage_path, mime_type")
    .eq("id", documentId)
    .maybeSingle();
  if (docErr) return json({ error: "db_error", detail: docErr.message }, 500);
  if (!doc) return json({ error: "document_not_found" }, 404);
  if ((doc as DocumentRow).user_id !== user.id) {
    return json({ error: "forbidden" }, 403);
  }

  const document = doc as DocumentRow;
  const mime = document.mime_type ?? "application/octet-stream";
  if (!isSupported(mime)) {
    await admin.from("documents").update({
      status: "failed",
      error: `unsupported_type: ${mime}`,
    }).eq("id", document.id);
    return json({ error: "unsupported_type", detail: mime }, 400);
  }

  // ─── Rate limit ───
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `ingest:${user.id}`,
    limit: 20,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  await admin.from("documents")
    .update({ status: "processing", error: null })
    .eq("id", document.id);

  // ─── Procesado en background ───
  // deno-lint-ignore no-explicit-any
  const waitUntil = (globalThis as any).EdgeRuntime?.waitUntil?.bind(
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime,
  );
  if (typeof waitUntil === "function") {
    waitUntil(processDocument(admin, document, mime));
  } else {
    await processDocument(admin, document, mime);
  }

  return json({ ok: true, document_id: document.id, status: "processing" }, 202);
}));

// deno-lint-ignore no-explicit-any
async function processDocument(
  admin: any,
  document: DocumentRow,
  mime: string,
): Promise<void> {
  try {
    const { data: blob, error: dlErr } = await admin.storage
      .from("temarios")
      .download(document.storage_path);
    if (dlErr || !blob) {
      throw new Error("download_failed: " + (dlErr?.message ?? "no_blob"));
    }
    const bytes = new Uint8Array(await blob.arrayBuffer());

    // PDF con capa de texto: extraemos el TEXTO COMPLETO sin IA ni truncado.
    if (mime === "application/pdf") {
      const pdfText = await extractPdfText(bytes);
      if (pdfText.trim().length >= 200) {
        await admin.from("documents").update({
          status: "ready",
          extracted_text: pdfText,
          error: null,
        }).eq("id", document.id);
        return;
      }
      // PDF escaneado (sin texto extraíble): seguimos al extractor por visión.
    }

    const system =
      "You are a document ingestion engine for a study app. Extract the full " +
      "readable text content of the provided material, preserving structure " +
      "(headings, lists, numbering). Detect the main language as an ISO 639-1 " +
      "code. Propose a short title. Respond ONLY with minified JSON of the " +
      'shape {"language":"xx","title":"...","text":"..."} and nothing else.';

    let messages: Array<{ role: "user"; content: string }>;
    let attachments: Array<{ mimeType: string; dataBase64: string }> | undefined;
    if (mime.startsWith("text/")) {
      const raw = new TextDecoder().decode(bytes).slice(0, 200000);
      messages = [{ role: "user", content: "Process this document:\n\n" + raw }];
      attachments = undefined;
    } else {
      messages = [{ role: "user", content: "Process the attached document." }];
      attachments = [{ mimeType: mime, dataBase64: toBase64(bytes) }];
    }

    const result = await runCompletion(admin, {
      task: "ingest",
      system,
      messages,
      attachments,
      maxOutputTokens: 8192,
      temperature: 0,
      userId: document.user_id,
      subjectId: document.subject_id,
    });

    const parsed = parseIngestJson(result.text);
    const extracted = (parsed.text ?? result.text ?? "").toString();
    const language = (parsed.language ?? "").toString().trim().slice(0, 8);

    await admin.from("documents").update({
      status: "ready",
      extracted_text: extracted,
      error: null,
    }).eq("id", document.id);

    // Fija el idioma del temario si aún no estaba definido.
    if (language) {
      await admin.from("subjects")
        .update({ language })
        .eq("id", document.subject_id)
        .is("language", null);
    }
  } catch (e) {
    const msg = e instanceof AiGatewayError
      ? e.message
      : (e as Error).message;
    await admin.from("documents").update({
      status: "failed",
      error: msg.slice(0, 500),
    }).eq("id", document.id);
    captureError(e, { fn: "ingest-document", document: document.id });
  }
}
