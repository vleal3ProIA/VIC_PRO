import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Dispara la descarga de un archivo JSON en el navegador. Crea un Blob con
/// el `payload` serializado e indented, un anchor invisible con
/// `download=<filename>`, lo añade al DOM, hace click y limpia. Es la forma
/// estándar de "descargar un archivo desde la app" en web sin tocar disco
/// desde el servidor.
///
/// Solo funciona en Flutter web (la app lo es). En otras plataformas
/// lanzaría un error de import — no añadimos stub porque el destino del
/// proyecto es web exclusivo.
void downloadJsonFile({
  required String filename,
  required Object payload,
}) {
  final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
  final parts = <JSAny>[jsonString.toJS].toJS;
  final blob = web.Blob(
    parts,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
