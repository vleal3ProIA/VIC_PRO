// ============================================================================
// _shared/ai/material.ts · Reúne el material de un temario para el modelo
// ----------------------------------------------------------------------------
// Devuelve el contenido de los documentos 'ready' de un temario en la forma
// que mejor aprovecha el modelo:
//   - PDF / imagen  -> adjunto (visión nativa): el modelo lee el documento
//                      ENTERO por el lado de ENTRADA (contexto enorme), sin el
//                      tope de salida que truncaba el texto extraído.
//   - texto         -> se incluye su `extracted_text` como contexto.
// Si el adjunto supera el límite inline, cae al `extracted_text` como respaldo.
// ============================================================================

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { AiAttachment } from "./types.ts";

// Límite total de adjuntos inline (Gemini admite ~20 MB inline por petición).
const MAX_ATTACH_BYTES = 18 * 1024 * 1024;
const MAX_TEXT_CHARS = 300000;

/// Deduce el mime real: respeta pdf/image/text; si es genérico o vacío, lo
/// infiere por la extensión del path en Storage.
function normalizeMime(mime: string | null, path: string): string {
  const m = (mime ?? "").toLowerCase();
  if (m === "application/pdf" || m.startsWith("image/") || m.startsWith("text/")) {
    return m;
  }
  const ext = path.toLowerCase().split(".").pop() ?? "";
  switch (ext) {
    case "pdf":
      return "application/pdf";
    case "png":
      return "image/png";
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "webp":
      return "image/webp";
    case "gif":
      return "image/gif";
    case "txt":
    case "md":
      return "text/plain";
    default:
      return m;
  }
}

export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

export interface SubjectMaterial {
  textContext: string;
  attachments: AiAttachment[];
}

export async function gatherMaterial(
  admin: SupabaseClient,
  subjectId: string,
): Promise<SubjectMaterial> {
  const { data } = await admin
    .from("documents")
    .select("mime_type, storage_path, extracted_text")
    .eq("subject_id", subjectId)
    .eq("status", "ready");
  const rows = (data ?? []) as Array<{
    mime_type: string | null;
    storage_path: string;
    extracted_text: string | null;
  }>;

  const textParts: string[] = [];
  const attachments: AiAttachment[] = [];
  let attachBytes = 0;

  for (const d of rows) {
    // mime robusto: si el navegador guardó un mime genérico/ausente, lo
    // deducimos por la extensión del archivo (el PDF se trataba como "texto"
    // y se caía al extracted_text truncado).
    const mime = normalizeMime(d.mime_type, d.storage_path);
    const isDoc = mime === "application/pdf" || mime.startsWith("image/");
    if (isDoc) {
      // Atachamos el PDF para proveedores con vision (Gemini, Anthropic).
      try {
        const { data: blob, error } = await admin.storage
          .from("temarios")
          .download(d.storage_path);
        if (!error && blob) {
          const bytes = new Uint8Array(await blob.arrayBuffer());
          if (attachBytes + bytes.length <= MAX_ATTACH_BYTES) {
            attachments.push({ mimeType: mime, dataBase64: toBase64(bytes) });
            attachBytes += bytes.length;
          }
        }
      } catch (_) {
        // Si falla el atach, no pasa nada: el extracted_text de abajo cubre.
      }
      // SIEMPRE incluir el extracted_text si existe (no solo cuando el atach
      // falla). Razon: proveedores SIN vision (Groq, OpenAI-compat) tambien
      // necesitan el texto para servir como fallback. Antes solo se incluia
      // como respaldo del atach -> Groq nunca recibia material -> el filtro
      // DOCUMENT_CAPABLE dejaba a Gemini como unico proveedor disponible.
      if (d.extracted_text) textParts.push(d.extracted_text);
    } else if (d.extracted_text) {
      textParts.push(d.extracted_text);
    }
  }

  let textContext = textParts.join("\n\n---\n\n");
  if (textContext.length > MAX_TEXT_CHARS) {
    textContext = textContext.slice(0, MAX_TEXT_CHARS);
  }
  return { textContext, attachments };
}
