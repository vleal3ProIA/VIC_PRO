// Tests del validador de magic bytes para avatares.
//
// Cubrimos:
//   - PNG, JPEG (5 variantes), GIF (87a + 89a), WEBP -> aceptan.
//   - Bytes truncados / vacios -> rechazan.
//   - MIME no en whitelist -> rechazan.
//   - MIME spoofing: bytes de JPEG con content-type 'image/png' -> rechazan.
//   - Wildcard de WEBP en bytes 4-7 (length): cualquier valor pasa.
//
// Estos tests no requieren red ni Storage; son puros sobre Uint8List.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/security/image_magic_bytes.dart';

/// Helper para construir Uint8List a partir de una lista de ints.
Uint8List _b(List<int> ints) => Uint8List.fromList(ints);

void main() {
  group('validateImageMagicBytes · PNG', () {
    test('acepta PNG con firma canonica', () {
      final bytes = _b([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        // payload arbitrario despues
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      ]);
      expect(validateImageMagicBytes(bytes, 'image/png'), isTrue);
    });

    test('rechaza PNG con firma truncada', () {
      // Solo 4 de los 8 bytes de la firma.
      final bytes = _b([0x89, 0x50, 0x4e, 0x47]);
      expect(validateImageMagicBytes(bytes, 'image/png'), isFalse);
    });

    test('rechaza si el segundo byte de PNG esta cambiado', () {
      final bytes = _b([
        0x89, 0xFF, // byte 1 corrupto (deberia ser 0x50)
        0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      ]);
      expect(validateImageMagicBytes(bytes, 'image/png'), isFalse);
    });
  });

  group('validateImageMagicBytes · JPEG', () {
    test('acepta JFIF (0xFFD8FFE0)', () {
      final bytes = _b([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);
      expect(validateImageMagicBytes(bytes, 'image/jpeg'), isTrue);
    });

    test('acepta EXIF (0xFFD8FFE1)', () {
      final bytes = _b([0xff, 0xd8, 0xff, 0xe1, 0x00, 0x20]);
      expect(validateImageMagicBytes(bytes, 'image/jpeg'), isTrue);
    });

    test('acepta Samsung variant (0xFFD8FFE8)', () {
      final bytes = _b([0xff, 0xd8, 0xff, 0xe8, 0x00, 0x10]);
      expect(validateImageMagicBytes(bytes, 'image/jpeg'), isTrue);
    });

    test('acepta Raw JPEG (0xFFD8FFDB)', () {
      final bytes = _b([0xff, 0xd8, 0xff, 0xdb, 0x00, 0x84]);
      expect(validateImageMagicBytes(bytes, 'image/jpeg'), isTrue);
    });

    test('rechaza variante desconocida (0xFFD8FF00)', () {
      // 0x00 no esta en las 5 variantes aceptadas.
      final bytes = _b([0xff, 0xd8, 0xff, 0x00, 0x00, 0x10]);
      expect(validateImageMagicBytes(bytes, 'image/jpeg'), isFalse);
    });
  });

  group('validateImageMagicBytes · GIF', () {
    test('acepta GIF87a', () {
      final bytes = _b([0x47, 0x49, 0x46, 0x38, 0x37, 0x61, 0x10, 0x00]);
      expect(validateImageMagicBytes(bytes, 'image/gif'), isTrue);
    });

    test('acepta GIF89a', () {
      final bytes = _b([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x10, 0x00]);
      expect(validateImageMagicBytes(bytes, 'image/gif'), isTrue);
    });

    test('rechaza GIF99a (no existe)', () {
      final bytes = _b([0x47, 0x49, 0x46, 0x38, 0x39, 0x39, 0x10, 0x00]);
      expect(validateImageMagicBytes(bytes, 'image/gif'), isFalse);
    });
  });

  group('validateImageMagicBytes · WEBP', () {
    test('acepta firma valida con cualquier longitud (wildcards)', () {
      final bytes = _b([
        0x52, 0x49, 0x46, 0x46, // "RIFF"
        0xab, 0xcd, 0xef, 0x12, // length (wildcards - cualquier valor)
        0x57, 0x45, 0x42, 0x50, // "WEBP"
        0x56, 0x50, 0x38, 0x20, // payload
      ]);
      expect(validateImageMagicBytes(bytes, 'image/webp'), isTrue);
    });

    test('acepta firma valida con longitud cero', () {
      final bytes = _b([
        0x52, 0x49, 0x46, 0x46,
        0x00, 0x00, 0x00, 0x00, // length = 0
        0x57, 0x45, 0x42, 0x50,
      ]);
      expect(validateImageMagicBytes(bytes, 'image/webp'), isTrue);
    });

    test('rechaza si los bytes 8-11 no son "WEBP" (ej. "AVI ")', () {
      final bytes = _b([
        0x52, 0x49, 0x46, 0x46, // "RIFF"
        0x10, 0x00, 0x00, 0x00,
        0x41, 0x56, 0x49, 0x20, // "AVI " -- formato distinto
      ]);
      expect(validateImageMagicBytes(bytes, 'image/webp'), isFalse);
    });

    test('rechaza si no empieza con "RIFF"', () {
      final bytes = _b([
        0x00, 0x49, 0x46, 0x46, // primer byte mal
        0x00, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50,
      ]);
      expect(validateImageMagicBytes(bytes, 'image/webp'), isFalse);
    });
  });

  group('validateImageMagicBytes · MIME spoofing', () {
    test('rechaza bytes de JPEG declarados como PNG', () {
      // Atacante manda image/png pero los bytes son JPEG.
      final jpegBytes = _b([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
      expect(validateImageMagicBytes(jpegBytes, 'image/png'), isFalse);
    });

    test('rechaza ejecutable PE declarado como PNG', () {
      // PE header empieza con "MZ" (0x4D 0x5A).
      final exeBytes = _b([0x4d, 0x5a, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00]);
      expect(validateImageMagicBytes(exeBytes, 'image/png'), isFalse);
    });

    test('rechaza HTML declarado como image/jpeg', () {
      // "<html"
      final htmlBytes = _b([0x3c, 0x68, 0x74, 0x6d, 0x6c, 0x3e]);
      expect(validateImageMagicBytes(htmlBytes, 'image/jpeg'), isFalse);
    });
  });

  group('validateImageMagicBytes · edge cases', () {
    test('rechaza buffer vacio', () {
      expect(validateImageMagicBytes(_b([]), 'image/png'), isFalse);
    });

    test('rechaza si MIME no esta en la whitelist', () {
      final pngBytes = _b([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      ]);
      // application/pdf NO esta en kAllowedAvatarMimes -> false aunque
      // los bytes empezaran con %PDF.
      expect(validateImageMagicBytes(pngBytes, 'application/pdf'), isFalse);
      expect(validateImageMagicBytes(pngBytes, 'image/svg+xml'), isFalse);
      expect(validateImageMagicBytes(pngBytes, ''), isFalse);
    });
  });

  group('kAllowedAvatarMimes', () {
    test('contiene exactamente PNG/JPEG/GIF/WEBP', () {
      expect(kAllowedAvatarMimes, hasLength(4));
      expect(
        kAllowedAvatarMimes,
        containsAll(<String>[
          'image/png',
          'image/jpeg',
          'image/gif',
          'image/webp',
        ]),
      );
    });

    test('NO contiene image/svg+xml (XSS vector)', () {
      // SVG puede contener <script> -- nunca debe estar en la
      // whitelist de avatar. Si alguien lo anyade en el futuro,
      // este test lo pilla.
      expect(kAllowedAvatarMimes.contains('image/svg+xml'), isFalse);
    });

    test('NO contiene image/bmp / image/tiff (no usados)', () {
      // Mantenemos la whitelist minima para reducir superficie.
      expect(kAllowedAvatarMimes.contains('image/bmp'), isFalse);
      expect(kAllowedAvatarMimes.contains('image/tiff'), isFalse);
    });
  });
}
