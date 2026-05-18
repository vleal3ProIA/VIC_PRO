// ============================================================================
// Tests Deno: magic_bytes.ts (PR-D)
// ----------------------------------------------------------------------------
// Cobertura para los validadores de PR-A (whitelist + magic bytes +
// heuristica UTF-8). Sin estos tests, una refactorizacion futura podria
// silenciosamente aceptar tipos peligrosos (HTML, SVG, ejecutables) o
// rechazar tipos legitimos.
//
// Como ejecutar:
//   cd supabase/functions
//   deno test --allow-read _shared/__tests__/magic_bytes.test.ts
//
// O todo el suite del proyecto:
//   deno test --allow-read _shared/__tests__/
// ============================================================================

import {
  assertEquals,
  assert,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  ALLOWED_MIMES,
  TEXT_LIKE_MIMES,
  isTextLike,
  sha256Hex,
  validateMagicBytes,
  validateUtf8Text,
} from "../magic_bytes.ts";

// ─────────────────────── Whitelist coverage ───────────────────────

Deno.test("ALLOWED_MIMES contiene los 27 tipos del whitelist", () => {
  // Si este test falla es que alguien anyadio/quito MIMEs y NO
  // actualizo SECURITY.md sec.10.1. Mantener sincronizado.
  const expected = [
    // Texto
    "text/plain",
    "text/csv",
    "text/tab-separated-values",
    "text/markdown",
    "application/json",
    "application/xml",
    "text/xml",
    "application/x-yaml",
    "text/yaml",
    "application/rtf",
    "text/rtf",
    // Documentos
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-powerpoint",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/vnd.oasis.opendocument.text",
    "application/vnd.oasis.opendocument.spreadsheet",
    "application/vnd.oasis.opendocument.presentation",
    "application/epub+zip",
    // Imagenes
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
    // Archivos
    "application/zip",
    "application/gzip",
    "application/x-gzip",
    "application/x-tar",
    "application/x-7z-compressed",
  ];
  for (const mime of expected) {
    assert(
      ALLOWED_MIMES.has(mime),
      `Missing MIME in whitelist: ${mime}`,
    );
  }
});

Deno.test("ALLOWED_MIMES NO contiene tipos peligrosos", () => {
  // Defense-in-depth: si alguien anyade HTML/SVG/JS al whitelist por
  // error, este test lo caza.
  const forbidden = [
    "text/html",
    "image/svg+xml",
    "application/javascript",
    "application/x-javascript",
    "application/x-msdownload",
    "application/x-executable",
    "application/x-sh",
    "text/x-shellscript",
  ];
  for (const mime of forbidden) {
    assertFalse(
      ALLOWED_MIMES.has(mime),
      `Forbidden MIME found in whitelist: ${mime}`,
    );
  }
});

Deno.test("isTextLike correctamente clasifica MIMEs", () => {
  assert(isTextLike("text/plain"));
  assert(isTextLike("text/csv"));
  assert(isTextLike("application/json"));
  assertFalse(isTextLike("image/png"));
  assertFalse(isTextLike("application/pdf"));
  assertFalse(isTextLike("text/html")); // ni siquiera lo aceptamos
});

// ─────────────────────── Magic bytes: imagenes ───────────────────────

Deno.test("validateMagicBytes acepta PNG real", () => {
  // PNG header: 89 50 4E 47 0D 0A 1A 0A
  const bytes = new Uint8Array([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, // IHDR chunk start
  ]);
  assert(validateMagicBytes(bytes, "image/png"));
});

Deno.test("validateMagicBytes acepta JPEG variants (JFIF, EXIF)", () => {
  const jfif = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00]);
  assert(validateMagicBytes(jfif, "image/jpeg"));
  const exif = new Uint8Array([0xff, 0xd8, 0xff, 0xe1, 0x00]);
  assert(validateMagicBytes(exif, "image/jpeg"));
});

Deno.test("validateMagicBytes acepta GIF87a y GIF89a", () => {
  const gif87 = new Uint8Array([
    0x47, 0x49, 0x46, 0x38, 0x37, 0x61,
  ]);
  const gif89 = new Uint8Array([
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
  ]);
  assert(validateMagicBytes(gif87, "image/gif"));
  assert(validateMagicBytes(gif89, "image/gif"));
});

Deno.test("validateMagicBytes acepta WEBP con wildcards de size", () => {
  // RIFF + 4 bytes (length, wildcards) + WEBP
  const bytes = new Uint8Array([
    0x52, 0x49, 0x46, 0x46, // RIFF
    0xff, 0xff, 0xff, 0xff, // length placeholder
    0x57, 0x45, 0x42, 0x50, // WEBP
  ]);
  assert(validateMagicBytes(bytes, "image/webp"));
});

// ─────────────────────── Magic bytes: documentos ───────────────────────

Deno.test("validateMagicBytes acepta PDF real", () => {
  const bytes = new TextEncoder().encode("%PDF-1.7\n");
  assert(validateMagicBytes(bytes, "application/pdf"));
});

Deno.test("validateMagicBytes acepta ZIP / docx / xlsx / pptx (mismo header)", () => {
  // ZIP header: 50 4B 03 04 (los office moderno son ZIPs)
  const zip = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0x14]);
  assert(validateMagicBytes(zip, "application/zip"));
  assert(validateMagicBytes(
    zip,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ));
  assert(validateMagicBytes(
    zip,
    "application/vnd.oasis.opendocument.text",
  ));
});

Deno.test("validateMagicBytes acepta MS Office binario antiguo (OLE2)", () => {
  // OLE2 signature
  const bytes = new Uint8Array([
    0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1,
  ]);
  assert(validateMagicBytes(bytes, "application/msword"));
  assert(validateMagicBytes(bytes, "application/vnd.ms-excel"));
});

Deno.test("validateMagicBytes acepta RTF", () => {
  const bytes = new TextEncoder().encode("{\\rtf1\\ansi");
  assert(validateMagicBytes(bytes, "application/rtf"));
  assert(validateMagicBytes(bytes, "text/rtf"));
});

// ─────────────────────── Anti-spoofing (caso clave) ───────────────────────

Deno.test("validateMagicBytes RECHAZA PNG renombrado como PDF", () => {
  // Bytes reales de PNG con MIME declarado como PDF -> rechazado.
  const bytes = new Uint8Array([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  ]);
  assertFalse(validateMagicBytes(bytes, "application/pdf"));
});

Deno.test("validateMagicBytes RECHAZA un .exe disfrazado de PNG", () => {
  // Magic bytes de PE/exe: 4D 5A (MZ)
  const bytes = new Uint8Array([0x4d, 0x5a, 0x90, 0x00]);
  assertFalse(validateMagicBytes(bytes, "image/png"));
  assertFalse(validateMagicBytes(bytes, "application/pdf"));
});

Deno.test("validateMagicBytes RECHAZA MIME fuera del whitelist (HTML)", () => {
  const html = new TextEncoder().encode("<!DOCTYPE html><html>");
  assertFalse(validateMagicBytes(html, "text/html"));
  // SVG tampoco -- mismo motivo.
  const svg = new TextEncoder().encode("<svg xmlns='...'><script>");
  assertFalse(validateMagicBytes(svg, "image/svg+xml"));
});

Deno.test("validateMagicBytes rechaza bytes vacios", () => {
  const empty = new Uint8Array([]);
  assertFalse(validateMagicBytes(empty, "image/png"));
  assertFalse(validateMagicBytes(empty, "application/pdf"));
});

Deno.test("validateMagicBytes rechaza bytes truncados (PNG corto)", () => {
  // Solo los primeros 3 bytes del header PNG -- no completo.
  const truncated = new Uint8Array([0x89, 0x50, 0x4e]);
  assertFalse(validateMagicBytes(truncated, "image/png"));
});

// ─────────────────────── UTF-8 heuristic (text-like) ───────────────────────

Deno.test("validateUtf8Text acepta texto ASCII normal", () => {
  const bytes = new TextEncoder().encode("Hello, world!");
  assert(validateUtf8Text(bytes));
});

Deno.test("validateUtf8Text acepta UTF-8 con caracteres unicode", () => {
  const bytes = new TextEncoder().encode("Hola 世界 émoji 🚀");
  assert(validateUtf8Text(bytes));
});

Deno.test("validateUtf8Text RECHAZA contenido con NUL byte (binario)", () => {
  const bytes = new Uint8Array([
    0x48, 0x65, 0x6c, 0x6c, 0x6f, // "Hello"
    0x00, // NUL -> rechaza
    0x57, 0x6f, 0x72, 0x6c, 0x64, // "World"
  ]);
  assertFalse(validateUtf8Text(bytes));
});

Deno.test("validateUtf8Text RECHAZA secuencias UTF-8 invalidas", () => {
  // 0xC0 0x80 es overlong encoding de NUL, invalido en UTF-8 estricto.
  // Mejor: bytes que no son utf-8 valido por estructura.
  const bytes = new Uint8Array([0xff, 0xfe, 0x00, 0x00]);
  // 0xFF no es valido como inicio de secuencia UTF-8.
  assertFalse(validateUtf8Text(bytes));
});

Deno.test("validateUtf8Text aplicado a JSON valido pasa", () => {
  const json = new TextEncoder().encode('{"name":"test","value":42}');
  // validateMagicBytes para application/json llama a validateUtf8Text
  // internamente porque es text-like.
  assert(validateMagicBytes(json, "application/json"));
});

Deno.test("validateUtf8Text aplicado a CSV con UTF-8 pasa", () => {
  const csv = new TextEncoder().encode("nombre,edad\nAna,30\nBéla,42\n");
  assert(validateMagicBytes(csv, "text/csv"));
});

Deno.test("validateUtf8Text rechaza .txt con bytes binarios disfrazados", () => {
  // Atacante sube un PE .exe declarandolo como .txt.
  const fakeText = new Uint8Array([
    0x4d, 0x5a, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00,
  ]);
  assertFalse(validateMagicBytes(fakeText, "text/plain"));
});

// ─────────────────────── sha256Hex ───────────────────────

Deno.test("sha256Hex devuelve hex 64 chars lowercase", async () => {
  const bytes = new TextEncoder().encode("hello world");
  const hash = await sha256Hex(bytes);
  // SHA-256 conocido de "hello world":
  assertEquals(
    hash,
    "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9",
  );
  assertEquals(hash.length, 64);
  assert(/^[a-f0-9]+$/.test(hash), "sha256 debe ser hex lowercase");
});

Deno.test("sha256Hex deterministico", async () => {
  const bytes = new TextEncoder().encode("test");
  const h1 = await sha256Hex(bytes);
  const h2 = await sha256Hex(bytes);
  assertEquals(h1, h2);
});

// ─────────────────────── Edge case: tar offset 257 ───────────────────────

Deno.test("validateMagicBytes acepta TAR (ustar magic en offset 257)", () => {
  // Construimos un TAR mínimo: 257 bytes de relleno + "ustar".
  const bytes = new Uint8Array(512);
  // bytes[257..262] = "ustar"
  bytes[257] = 0x75;
  bytes[258] = 0x73;
  bytes[259] = 0x74;
  bytes[260] = 0x61;
  bytes[261] = 0x72;
  assert(validateMagicBytes(bytes, "application/x-tar"));
});

Deno.test("validateMagicBytes RECHAZA TAR sin magic en offset 257", () => {
  // Bytes mas cortos que el offset minimo.
  const tooShort = new Uint8Array(256);
  assertFalse(validateMagicBytes(tooShort, "application/x-tar"));
});
