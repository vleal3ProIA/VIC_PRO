// ============================================================================
// Helper compartido: validacion de magic bytes + heuristica UTF-8
// ----------------------------------------------------------------------------
// Defensa contra MIME spoofing en uploads: un atacante puede declarar
// `Content-Type: image/png` y subir un .exe renombrado. Si confiamos en
// el header, se cuela. Comparando los primeros bytes del archivo contra
// firmas conocidas, lo cazamos.
//
// **Limitaciones**:
//   - No detecta polyglots (archivos validos como dos formatos). Para
//     eso haria falta inspeccion semantica completa.
//   - No detecta payloads embebidos en formatos legitimos (ej. JS
//     dentro de PDF). Para eso necesitamos antivirus (PR-C).
//
// **Estrategia**:
//   - Tabla `MAGIC_BYTE_SIGNATURES` con array de firmas por MIME.
//     Algunas familias (JPEG, WEBP) tienen varias firmas posibles.
//   - Para tipos texto (text/*, json, xml, yaml), no hay magic bytes
//     universales -- aplicamos heuristica: no `\x00` y decodificable
//     como UTF-8 en los primeros 8 KB.
//   - Para tipos office (docx, xlsx, pptx, odt, ods, odp, epub) que
//     internamente son ZIPs, validamos la firma ZIP. La verificacion
//     del mimetype interno (que distingue docx de odt) la dejamos para
//     una iteracion futura -- el riesgo de subir un docx que en
//     realidad es xlsx es bajo (no es vector de ataque).
//
// **Tests**: ver supabase/functions/_shared/__tests__/magic_bytes.test.ts
// (creado en PR-D).
// ============================================================================

// Cada signature es un array de bytes. Si todos coinciden en orden
// desde offset 0 (o el offset indicado), el archivo matchea.
// `null` en una posicion = wildcard (cualquier byte).
export interface Signature {
  bytes: (number | null)[];
  offset?: number; // default 0
}

const PNG: Signature = {
  bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
};

const JPEG_VARIANTS: Signature[] = [
  // JFIF
  { bytes: [0xff, 0xd8, 0xff, 0xe0] },
  // EXIF
  { bytes: [0xff, 0xd8, 0xff, 0xe1] },
  // Samsung / various
  { bytes: [0xff, 0xd8, 0xff, 0xe8] },
  // Raw JPEG
  { bytes: [0xff, 0xd8, 0xff, 0xdb] },
  // Canon CR2 / generic
  { bytes: [0xff, 0xd8, 0xff, 0xee] },
];

const GIF_VARIANTS: Signature[] = [
  // GIF87a
  { bytes: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61] },
  // GIF89a
  { bytes: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61] },
];

const WEBP: Signature = {
  // "RIFF" + 4 bytes length + "WEBP"
  bytes: [
    0x52,
    0x49,
    0x46,
    0x46,
    null,
    null,
    null,
    null,
    0x57,
    0x45,
    0x42,
    0x50,
  ],
};

const PDF: Signature = {
  bytes: [0x25, 0x50, 0x44, 0x46, 0x2d], // %PDF-
};

const ZIP: Signature = {
  bytes: [0x50, 0x4b, 0x03, 0x04], // PK\x03\x04
};

// ZIPs vacios o spanned (rare) tienen otras firmas. Aceptamos solo la
// principal -- los office docs siempre la usan.

const RTF: Signature = {
  bytes: [0x7b, 0x5c, 0x72, 0x74, 0x66, 0x31], // {\rtf1
};

const GZIP: Signature = {
  bytes: [0x1f, 0x8b],
};

const TAR: Signature = {
  bytes: [0x75, 0x73, 0x74, 0x61, 0x72], // 'ustar' at offset 257
  offset: 257,
};

const SEVENZ: Signature = {
  bytes: [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c],
};

// Old MS Office binary format (doc, xls, ppt pre-2007) usa OLE2
// compound file. Firma: D0 CF 11 E0 A1 B1 1A E1.
const OLE2: Signature = {
  bytes: [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1],
};

// ────────────────────────── MIME → signatures ──────────────────────────

const MAGIC_BYTE_SIGNATURES: Record<string, Signature[]> = {
  // Imagenes
  "image/png": [PNG],
  "image/jpeg": JPEG_VARIANTS,
  "image/gif": GIF_VARIANTS,
  "image/webp": [WEBP],

  // PDF
  "application/pdf": [PDF],

  // RTF
  "application/rtf": [RTF],
  "text/rtf": [RTF], // algunos clientes mandan este content-type

  // Archivos
  "application/zip": [ZIP],
  "application/gzip": [GZIP],
  "application/x-gzip": [GZIP],
  "application/x-tar": [TAR],
  "application/x-7z-compressed": [SEVENZ],

  // MS Office moderno (todos son ZIPs internamente)
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
    [ZIP],
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
    [ZIP],
  "application/vnd.openxmlformats-officedocument.presentationml.presentation":
    [ZIP],

  // MS Office binario antiguo
  "application/msword": [OLE2],
  "application/vnd.ms-excel": [OLE2],
  "application/vnd.ms-powerpoint": [OLE2],

  // OpenDocument (tambien ZIPs)
  "application/vnd.oasis.opendocument.text": [ZIP],
  "application/vnd.oasis.opendocument.spreadsheet": [ZIP],
  "application/vnd.oasis.opendocument.presentation": [ZIP],

  // EPUB (ZIP con mimetype interno)
  "application/epub+zip": [ZIP],
};

// Tipos que NO tienen magic bytes universales -- validamos con
// heuristica UTF-8.
export const TEXT_LIKE_MIMES = new Set<string>([
  "text/plain",
  "text/csv",
  "text/tab-separated-values",
  "text/markdown",
  "application/json",
  "application/xml",
  "text/xml",
  "application/x-yaml",
  "text/yaml",
]);

// Whitelist completa de MIMEs aceptados. Si el header content-type no
// esta aqui, rechazamos antes de mirar bytes.
export const ALLOWED_MIMES = new Set<string>([
  ...Object.keys(MAGIC_BYTE_SIGNATURES),
  ...TEXT_LIKE_MIMES,
]);

// ────────────────────────────── Validators ──────────────────────────────

/**
 * Comprueba que `bytes` empieza con una firma valida para `mime`.
 * Si `mime` es text-like, llama a `validateUtf8Text`.
 * Si `mime` no esta en el whitelist, devuelve false.
 */
export function validateMagicBytes(
  bytes: Uint8Array,
  mime: string,
): boolean {
  // Text-like: heuristica UTF-8 en lugar de magic bytes.
  if (TEXT_LIKE_MIMES.has(mime)) {
    return validateUtf8Text(bytes);
  }

  const signatures = MAGIC_BYTE_SIGNATURES[mime];
  if (!signatures) return false;

  // Acepta si CUALQUIERA de las signatures matchea.
  return signatures.some((sig) => matchSignature(bytes, sig));
}

function matchSignature(bytes: Uint8Array, sig: Signature): boolean {
  const offset = sig.offset ?? 0;
  if (bytes.length < offset + sig.bytes.length) return false;
  for (let i = 0; i < sig.bytes.length; i++) {
    const expected = sig.bytes[i];
    if (expected === null) continue; // wildcard
    if (bytes[offset + i] !== expected) return false;
  }
  return true;
}

/**
 * Heuristica para tipos texto: rechaza si hay NUL bytes o si los
 * primeros `sampleSize` bytes no son UTF-8 valido.
 *
 * NO garantiza al 100% que el contenido sea seguro -- un archivo
 * legitimo de codigo fuente con caracteres unicode raros pasaria,
 * mientras que un binario disfrazado de .txt seria rechazado en cuanto
 * apareciera un NUL. Suficiente para nuestro modelo de amenazas.
 */
export function validateUtf8Text(
  bytes: Uint8Array,
  sampleSize = 8192,
): boolean {
  const sample = bytes.subarray(0, Math.min(bytes.length, sampleSize));

  // 1) Sin NUL bytes -- ninguna codificacion textual real los tiene.
  for (let i = 0; i < sample.length; i++) {
    if (sample[i] === 0x00) return false;
  }

  // 2) Debe decodificar como UTF-8 sin errores.
  try {
    new TextDecoder("utf-8", { fatal: true }).decode(sample);
    return true;
  } catch {
    return false;
  }
}

/**
 * Calcula SHA-256 de un Uint8Array. Devuelve hex lowercase de 64 chars.
 * Usado para almacenar en `uploads.sha256` (deduplicacion + VirusTotal
 * lookup en PR-C).
 */
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Devuelve true si el MIME esta en la whitelist Y es text-like.
 * Helper de conveniencia para el upload-file.
 */
export function isTextLike(mime: string): boolean {
  return TEXT_LIKE_MIMES.has(mime);
}
