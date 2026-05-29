// ============================================================================
// data_export_html_builder.dart
// ----------------------------------------------------------------------------
// README HTML del ZIP "Descargar mis datos" (GDPR v4 · multi-formato).
//
// Se renderiza como `LEEME.html` / `README.html` al nivel raíz del ZIP y
// explica al usuario qué hay dentro y para qué sirve cada archivo. El HTML
// es **autocontenido**: no usa CSS externo, JS ni imágenes — solo
// `<style>` inline y unas pocas reglas para que se vea bien en móvil y
// escritorio sin conexión.
//
// El call-site (notifier) le pasa:
//   * `data`: el Map limpio devuelto por la RPC v3 (`get_my_data_export`).
//     De ahí extraemos los contadores agregados para el resumen.
//   * `labels`: el mismo `PdfExportLabels` que usan PDF y CSV builders.
//   * `localizedFilenames`: el nombre exacto que el notifier ha asignado
//     a cada fichero dentro del ZIP (puede variar por idioma —
//     `archivos.csv` vs `files.csv`). Lo recibimos como Map para no
//     duplicar el mapeo locale → filename.
//   * `formattedDate`: ya formateada por el call-site (sabe el locale).
//   * `brandName`: por defecto "myapp", inyectable por si en el futuro
//     cambiamos de marca o lo deployamos white-label.
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:myapp/features/account/presentation/util/data_export_pdf_builder.dart';

/// Nombres canónicos (en inglés) de cada fichero del ZIP. El call-site
/// pasa un map con la traducción correspondiente al idioma del usuario;
/// estos keys son la identidad estable usada en código.
enum ExportFile { readme, pdf, json, uploadsCsv, activityCsv, emailsCsv }

/// Construye el README.html del ZIP.
///
/// El parámetro `localizedFilenames` debe contener entradas para
/// **todos** los `ExportFile` excepto `readme` (no listamos el propio
/// README en el listado de ficheros — sería ruido).
Uint8List buildReadmeHtml({
  required Map<String, dynamic> data,
  required PdfExportLabels labels,
  required Map<ExportFile, String> localizedFilenames,
  required String formattedDate,
  String brandName = 'myapp',
}) {
  // ── Contadores agregados para el bloque "Resumen rápido" ──
  final uploads = _asList(data['uploads']);
  final emails = _asList(data['emails_received']);
  final audit = _asMap(data['audit_logs']);
  final loginSummary = _asMap(audit['login_summary']);
  final loginTotal = (loginSummary['total'] as num?)?.toInt() ?? 0;
  final otherEvents = _asList(audit['other_events']);

  final subtitle = labels.subtitle.replaceAll('{date}', formattedDate);

  // ── Helper para que cada fila del listado de ficheros se renderice
  //    igual sin repetir el bloque <li><code>...</code> ... ──
  String fileItem(ExportFile id, String desc) {
    final name = localizedFilenames[id] ?? id.name;
    return '<li><code>${_esc(name)}</code> — ${_esc(desc)}</li>';
  }

  final summaryLines = <String>[
    _li(labels.totalUploadsBuilder(uploads.length)),
    _li(labels.totalLoginsBuilder(loginTotal)),
    _li(labels.totalEventsBuilder(otherEvents.length)),
    _li(labels.totalEmailsBuilder(emails.length)),
  ].join('\n        ');

  final filesBlock = <String>[
    fileItem(ExportFile.pdf, labels.filePdfDesc),
    fileItem(ExportFile.json, labels.fileJsonDesc),
    fileItem(ExportFile.uploadsCsv, labels.fileUploadsCsvDesc),
    fileItem(ExportFile.activityCsv, labels.fileActivityCsvDesc),
    fileItem(ExportFile.emailsCsv, labels.fileEmailsCsvDesc),
  ].join('\n        ');

  final footer = _esc(
    labels.readmeGeneratedByBuilder(formattedDate, brandName),
  );

  // ── Template HTML autocontenido ──
  //
  // CSS reset mínimo + tipografía system + paleta neutra (gris/azul).
  // `max-width: 720px` + centrado ⇒ mobile-friendly sin media queries.
  final html =
      '''
<!DOCTYPE html>
<html lang="${_htmlLangFromTitle(labels.title)}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${_esc(labels.title)}</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 32px 16px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
        "Helvetica Neue", Arial, sans-serif;
      background: #f6f7f9;
      color: #1f2937;
      line-height: 1.5;
    }
    .wrap {
      max-width: 720px;
      margin: 0 auto;
      background: #ffffff;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06),
                  0 2px 8px rgba(0, 0, 0, 0.04);
      overflow: hidden;
    }
    header {
      background: #1976d2;
      color: #ffffff;
      padding: 28px 32px 22px;
    }
    h1 {
      margin: 0 0 6px;
      font-size: 22px;
      font-weight: 700;
      letter-spacing: -0.01em;
    }
    header p {
      margin: 0;
      font-size: 13px;
      opacity: 0.92;
    }
    main { padding: 24px 32px 32px; }
    section { margin-top: 28px; }
    section:first-of-type { margin-top: 0; }
    h2 {
      margin: 0 0 12px;
      font-size: 15px;
      font-weight: 700;
      color: #374151;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .notice {
      background: #fef3c7;
      border-left: 3px solid #d97706;
      padding: 12px 16px;
      font-size: 13px;
      color: #78350f;
      border-radius: 4px;
    }
    .intro {
      font-size: 14px;
      color: #4b5563;
      margin: 14px 0 0;
    }
    ul {
      margin: 0;
      padding-left: 22px;
    }
    li {
      margin: 6px 0;
      font-size: 14px;
    }
    code {
      background: #f3f4f6;
      padding: 2px 6px;
      border-radius: 3px;
      font-family: "SF Mono", Menlo, Consolas, Monaco, monospace;
      font-size: 12.5px;
      color: #1f2937;
    }
    footer {
      border-top: 1px solid #e5e7eb;
      padding: 18px 32px 22px;
      font-size: 12px;
      color: #6b7280;
      text-align: right;
    }
    @media (max-width: 480px) {
      body { padding: 16px 8px; }
      header { padding: 20px 20px 18px; }
      main { padding: 18px 20px 22px; }
      footer { padding: 14px 20px 18px; }
      h1 { font-size: 20px; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <h1>${_esc(labels.title)}</h1>
      <p>${_esc(subtitle)}</p>
    </header>
    <main>
      <section>
        <p class="notice">${_esc(labels.notice)}</p>
        <p class="intro">${_esc(labels.readmeIntro)}</p>
      </section>
      <section>
        <h2>${_esc(labels.readmeFilesTitle)}</h2>
        <ul>
        $filesBlock
        </ul>
      </section>
      <section>
        <h2>${_esc(labels.readmeSummaryTitle)}</h2>
        <ul>
        $summaryLines
        </ul>
      </section>
    </main>
    <footer>$footer</footer>
  </div>
</body>
</html>
''';

  return Uint8List.fromList(utf8.encode(html));
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

/// Escape HTML básico para los textos que insertamos en plantillas.
/// Cubrimos los 5 caracteres del subset XML (`&`, `<`, `>`, `"`, `'`)
/// — suficiente porque NO insertamos atributos calculados con texto del
/// usuario (el único `lang="..."` viene de un set cerrado de códigos ISO).
String _esc(String raw) {
  return raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _li(String text) => '<li>${_esc(text)}</li>';

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  return const {};
}

List<dynamic> _asList(Object? raw) {
  if (raw is List) return raw;
  return const [];
}

/// Heurística mínima para `<html lang="...">` a partir del título
/// localizado — sin necesidad de pasarle al builder un parámetro extra.
/// El title es una string ya conocida en el bundle (8 idiomas); por
/// ahora detectamos solo cuando hay caracteres cirílicos para distinguir
/// `ru`/`uk`; el resto cae a `en` por defecto, suficiente para que el
/// browser/lector elija el word-break correcto. No es crítico (el HTML
/// se lee localmente sin SEO), pero es buena práctica accesible.
String _htmlLangFromTitle(String title) {
  if (title.contains(RegExp('[А-Яа-яЁё]'))) return 'ru';
  if (title.contains(RegExp('[ІіЇїЄєҐґ]'))) return 'uk';
  if (title.contains('persönlich')) return 'de';
  if (title.contains('personnelles')) return 'fr';
  if (title.contains('personali')) return 'it';
  if (title.contains('pessoais')) return 'pt';
  if (title.contains('personales')) return 'es';
  return 'en';
}
