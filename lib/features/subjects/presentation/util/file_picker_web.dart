// ============================================================================
// subjects · Selector de archivo (web) — sin dependencias nuevas
// ----------------------------------------------------------------------------
// Crea un <input type="file"> oculto, lee el archivo elegido como bytes y
// devuelve nombre + mime + bytes. Mismo enfoque que `web_download.dart`
// (package:web + dart:js_interop). El proyecto es web-only, así que no hay
// stub de plataforma.
// ============================================================================

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class PickedFile {
  PickedFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// Abre el diálogo de selección de archivo del navegador. Devuelve el archivo
/// elegido, o `null` si el usuario cancela o falla la lectura.
Future<PickedFile?> pickFile({
  String accept = '.pdf,.txt,.md,image/*',
}) {
  final completer = Completer<PickedFile?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = accept;

  input.onchange = ((web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();
    reader.onload = ((web.Event _) {
      final res = reader.result;
      if (res == null) {
        completer.complete(null);
        return;
      }
      final buffer = (res as JSArrayBuffer).toDart;
      completer.complete(
        PickedFile(
          name: file.name,
          mimeType: file.type.isEmpty ? 'application/octet-stream' : file.type,
          bytes: buffer.asUint8List(),
        ),
      );
    }).toJS;
    reader.onerror = ((web.Event _) => completer.complete(null)).toJS;
    reader.readAsArrayBuffer(file);
  }).toJS;

  input.click();
  return completer.future;
}

/// Abre una URL en una pestaña nueva (para ver el documento original).
void openUrlInNewTab(String url) {
  web.window.open(url, '_blank');
}
