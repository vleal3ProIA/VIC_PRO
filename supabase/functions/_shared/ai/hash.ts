// ============================================================================
// _shared/ai/hash.ts · Hash de contenido de sección (clave del pool global)
// ----------------------------------------------------------------------------
// MISMA fórmula que ya usa generate-exam para `content_hash`, extraída a un
// módulo compartido para que el banco de preguntas, el pool de secciones y la
// detección de duplicados usen EXACTAMENTE la misma clave. Cambiar esto rompe
// la reutilización: no tocar la normalización sin migrar los hashes.
// ============================================================================

/// Normaliza: recorta, minúsculas, colapsa espacios. (igual que generate-exam)
export function normText(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, " ");
}

export async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(s),
  );
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// Clave de contenido de una sección: SHA-256 del texto normalizado (acotado a
/// 100k chars, igual que generate-exam).
export function contentHash(text: string): Promise<string> {
  return sha256Hex(normText(text).slice(0, 100_000));
}

/// Huella del DOCUMENTO completo (texto extraído normalizado, SIN acotar): dos
/// subidas idénticas dan la misma huella -> permite reutilizar/clonar el índice
/// ya generado sin volver a gastar IA.
export function docFingerprint(text: string): Promise<string> {
  return sha256Hex(normText(text));
}
