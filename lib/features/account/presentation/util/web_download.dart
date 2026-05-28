import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

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
  _triggerDownload(blob, filename);
}

/// Dispara la descarga de un archivo ZIP a partir de bytes ya construidos.
///
/// Lo usa el flow "Descargar mis datos" (GDPR v2): el notifier construye
/// un ZIP en memoria con `mis-datos.json` + `mis-datos.pdf` y lo entrega
/// aquí como `Uint8List`.
///
/// La firma acepta `Uint8List` (no `Object` como [downloadJsonFile]) para
/// que sea evidente que el caller ya hizo el encoding — esta función NO
/// reserializa nada, solo envuelve los bytes en un Blob con MIME zip.
void downloadZipFile({
  required String filename,
  required Uint8List bytes,
}) {
  // `toJS` sobre Uint8List produce un Uint8Array; el constructor de Blob
  // acepta BlobPart, que admite ArrayBufferView (Uint8Array lo es).
  final parts = <JSAny>[bytes.toJS].toJS;
  final blob = web.Blob(
    parts,
    web.BlobPropertyBag(type: 'application/zip'),
  );
  _triggerDownload(blob, filename);
}

/// Helper compartido — crea un anchor con `download`, lo clickea y limpia.
/// Privado al módulo; los dos `downloadXFile` públicos lo invocan.
void _triggerDownload(web.Blob blob, String filename) {
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
