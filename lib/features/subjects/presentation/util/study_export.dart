// ============================================================================
// subjects · Descarga de contenido generado (Fase 3)
// ----------------------------------------------------------------------------
// Dispara la descarga de un archivo de texto (Markdown) en el navegador.
// Mismo patrón que `audit_center/.../audit_txt_download.dart`. Solo web.
// ============================================================================

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Descarga [text] como un archivo [filename] (Markdown/texto) en el navegador.
void downloadStudyText({required String filename, required String text}) {
  final parts = <JSAny>[text.toJS].toJS;
  final blob = web.Blob(
    parts,
    web.BlobPropertyBag(type: 'text/markdown;charset=utf-8'),
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
