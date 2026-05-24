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
    const mime = d.mime_type ?? "";
    const isDoc = mime === "application/pdf" || mime.startsWith("image/");
    if (isDoc) {
      let attached = false;
      try {
        const { data: blob, error } = await admin.storage
          .from("temarios")
          .download(d.storage_path);
        if (!error && blob) {
          const bytes = new Uint8Array(await blob.arrayBuffer());
          if (attachBytes + bytes.length <= MAX_ATTACH_BYTES) {
            attachments.push({ mimeType: mime, dataBase64: toBase64(bytes) });
            attachBytes += bytes.length;
            attached = true;
          }
        }
      } catch (_) {
        // cae al extracted_text de abajo
      }
      if (!attached && d.extracted_text) textParts.push(d.extracted_text);
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
