// ============================================================================
// Audit Center · TXT download trigger (PR-Audit-3)
// ----------------------------------------------------------------------------
// Boton "Descargar TXT" en la detail page del audit. Crea un Blob con
// el texto plano renderizado y dispara el download via `<a download>`.
// Mismo patron que `account/presentation/util/web_download.dart`.
//
// Solo funciona en Flutter Web (el target del proyecto).
// ============================================================================

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Dispara la descarga de un .txt en el navegador. El `text` se
/// encapsula en un Blob `text/plain;charset=utf-8` y se "clickea" un
/// anchor invisible con `download=<filename>`.
void downloadTextFile({
  required String filename,
  required String text,
}) {
  final parts = <JSAny>[text.toJS].toJS;
  final blob = web.Blob(
    parts,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
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
