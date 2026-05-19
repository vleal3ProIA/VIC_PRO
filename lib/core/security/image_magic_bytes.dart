// ============================================================================
// Helper: validacion de magic bytes para imagenes (client-side)
// ----------------------------------------------------------------------------
// Defensa contra MIME spoofing en avatar uploads. Un atacante podria
// declarar `Content-Type: image/png` y subir un .exe renombrado a
// `.png`. Si confiamos solo en el header o en la extension, se cuela
// al bucket `avatars` de Supabase Storage, donde queda publicamente
// servido para cualquier viewer.
//
// **Estrategia**: comprobar los primeros bytes contra firmas
// conocidas. Si no matchean, rechazamos client-side ANTES de subirlo.
//
// **Espejo del helper TS** (`supabase/functions/_shared/magic_bytes.ts`,
// creado en PR-C Day 1). Mantenemos las mismas firmas para que el
// comportamiento sea consistente entre uploads generales (que pasan
// por la Edge Function `upload-file`) y avatares (que van directo al
// Storage desde el cliente).
//
// **Limitaciones**:
//   - Validacion **client-side**. Un atacante determinado puede
//     bypassear el cliente y subir directo al endpoint REST de
//     Supabase Storage con cualquier byte. Para defense in depth real
//     necesitariamos un endpoint Edge Function intermediario que
//     valide server-side (igual que upload-file). Esta validacion
//     client-side cubre el ataque casual / accidental + UX (rechazo
//     temprano).
//   - No detecta polyglots (archivos validos como dos formatos
//     simultaneamente). Para eso haria falta inspeccion semantica.
//   - No detecta payloads embebidos. Para eso necesitamos antivirus
//     (VirusTotal en uploads generales -- PR-C).
//
// **Tests**: `test/core/security/image_magic_bytes_test.dart`.
// ============================================================================

import 'dart:typed_data';

/// Una signature es una secuencia de bytes esperados desde un offset.
/// `null` significa wildcard (cualquier byte vale en esa posicion).
class ImageSignature {
  const ImageSignature({
    required this.bytes,
    this.offset = 0,
  });

  final List<int?> bytes;
  final int offset;
}

// ─────────────────────── Firmas por formato ───────────────────────

const ImageSignature _png = ImageSignature(
  bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
);

// JPEG tiene varios "magic numbers" segun el encoder. Aceptamos los
// 5 mas comunes (cubre > 99% de imagenes reales).
const List<ImageSignature> _jpegVariants = [
  ImageSignature(bytes: [0xff, 0xd8, 0xff, 0xe0]), // JFIF
  ImageSignature(bytes: [0xff, 0xd8, 0xff, 0xe1]), // EXIF
  ImageSignature(bytes: [0xff, 0xd8, 0xff, 0xe8]), // Samsung / varios
  ImageSignature(bytes: [0xff, 0xd8, 0xff, 0xdb]), // Raw JPEG
  ImageSignature(bytes: [0xff, 0xd8, 0xff, 0xee]), // Canon CR2 / generic
];

const List<ImageSignature> _gifVariants = [
  ImageSignature(bytes: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]), // GIF87a
  ImageSignature(bytes: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]), // GIF89a
];

// WEBP = "RIFF" + 4 bytes (longitud del file) + "WEBP".
// Los 4 bytes intermedios son la longitud y NO los comprobamos.
const ImageSignature _webp = ImageSignature(
  bytes: [
    0x52, 0x49, 0x46, 0x46, // "RIFF"
    null, null, null, null, // longitud (wildcards)
    0x57, 0x45, 0x42, 0x50, // "WEBP"
  ],
);

/// Whitelist de MIMEs aceptados para avatar. Si el header no esta
/// aqui, rechazamos antes de mirar bytes.
const Set<String> kAllowedAvatarMimes = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
};

const Map<String, List<ImageSignature>> _signaturesByMime = {
  'image/png': [_png],
  'image/jpeg': _jpegVariants,
  'image/gif': _gifVariants,
  'image/webp': [_webp],
};

// ─────────────────────── API publica ───────────────────────

/// `true` si `bytes` empieza con una firma valida para `mime`. Devuelve
/// `false` si:
///   - `mime` no esta en `kAllowedAvatarMimes`.
///   - Ninguna firma del MIME matchea los primeros bytes.
///   - `bytes` es demasiado corto para contener la firma.
///
/// **Diseno**: pura, sin side effects, testeable trivialmente. La UI
/// la llama desde el notifier antes de invocar la subida a Storage.
bool validateImageMagicBytes(Uint8List bytes, String mime) {
  final signatures = _signaturesByMime[mime];
  if (signatures == null) return false;
  return signatures.any((sig) => _matchSignature(bytes, sig));
}

bool _matchSignature(Uint8List bytes, ImageSignature sig) {
  final required = sig.offset + sig.bytes.length;
  if (bytes.length < required) return false;
  for (var i = 0; i < sig.bytes.length; i++) {
    final expected = sig.bytes[i];
    if (expected == null) continue; // wildcard
    if (bytes[sig.offset + i] != expected) return false;
  }
  return true;
}
