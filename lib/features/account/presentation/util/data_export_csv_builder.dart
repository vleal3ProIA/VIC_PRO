// ============================================================================
// data_export_csv_builder.dart
// ----------------------------------------------------------------------------
// Construye los CSVs que acompañan al PDF + JSON dentro del ZIP de
// "Descargar mis datos" (GDPR v4 · estilo Google Takeout, multi-formato).
//
// - 3 builders puros (uploads / actividad / correos) → `Uint8List`.
// - Sin Flutter widgets; reutilizable, testeable.
// - Las cabeceras son strings ya localizadas (vienen vía `PdfExportLabels`,
//   el mismo bundle que usa el PDF builder — una sola fuente de verdad).
// - UTF-8 con **BOM** (`﻿`) al principio para que Excel abra los
//   ficheros con la codificación correcta en caracteres no-ASCII
//   (ñ, ü, ё, ї…). Sin el BOM, Excel asume Windows-1252 y rompe acentos.
// - Fechas en ISO 8601 (`2026-05-22T17:16:06+00:00`): universal, sortable,
//   importable por Excel y Google Sheets.
// - Tamaños en bytes crudos (el usuario formatea si quiere).
//
// Si una sección no tiene entradas, el CSV se sigue exportando con SOLO la
// fila de cabecera (el notifier lo controla; aquí solo recibimos la lista
// vacía y la respetamos).
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import 'package:myapp/features/account/presentation/util/data_export_pdf_builder.dart';

// ─────────────────────────────────────────────────────────────────────
// API pública
// ─────────────────────────────────────────────────────────────────────

/// CSV con los archivos subidos por el usuario.
///
/// Columnas: nombre, tipo (mime original), tamaño en bytes, fecha ISO
/// 8601, marca de borrado (`yes`/`no` localizado).
Uint8List buildUploadsCsv(
  Map<String, dynamic> data,
  PdfExportLabels labels,
) {
  final rows = <List<dynamic>>[
    [
      labels.labelName,
      labels.labelKind,
      labels.labelSize,
      labels.labelDate,
      labels.labelDeleted,
    ],
  ];

  final uploads = _asList(data['uploads']);
  for (final raw in uploads) {
    final u = _asMap(raw);
    final deletedLabel =
        u['deleted_at'] != null ? labels.yes : labels.no;
    rows.add([
      (u['filename'] as String?) ?? '',
      (u['kind'] as String?) ?? '',
      (u['size_bytes'] as num?)?.toInt() ?? 0,
      _toIso(u['uploaded_at']),
      deletedLabel,
    ]);
  }

  return _encodeCsv(rows);
}

/// CSV con la actividad: primera fila es el resumen agregado de logins
/// (`event="login_summary"`, `count` en metadata, `occurred_at = last_at`),
/// resto son los eventos no-login del audit log.
///
/// Columnas: event, count, metadata, occurred_at.
Uint8List buildActivityCsv(
  Map<String, dynamic> data,
  PdfExportLabels labels,
) {
  final rows = <List<dynamic>>[
    [
      'event',
      'count',
      'metadata',
      'occurred_at',
    ],
  ];

  final audit = _asMap(data['audit_logs']);

  // Primera fila: resumen de logins (si el usuario hizo al menos 1 login).
  final summary = _asMap(audit['login_summary']);
  final total = (summary['total'] as num?)?.toInt() ?? 0;
  if (total > 0) {
    final firstAt = _toIso(summary['first_at']);
    final lastAt = _toIso(summary['last_at']);
    // metadata como JSON inline: `{"first_at":"...","label":"..."}`.
    // Excel lo trata como texto plano; quien parsee el CSV obtiene un
    // string parseable como JSON si lo necesita.
    final meta = jsonEncode({
      'first_at': firstAt,
      'label': labels.csvHeaderLogin,
    });
    rows.add([
      'login_summary',
      total,
      meta,
      lastAt,
    ]);
  }

  // Resto: otros eventos.
  final others = _asList(audit['other_events']);
  for (final raw in others) {
    final e = _asMap(raw);
    final ev = (e['event'] as String?) ?? '';
    final evMeta = _asMap(e['metadata']);
    // Metadata serializada como JSON para conservar la estructura sin
    // perder info al aplastar a string.
    final meta = evMeta.isEmpty ? '' : jsonEncode(evMeta);
    rows.add([
      ev,
      1, // un evento = 1, mismo schema que login_summary.
      meta,
      _toIso(e['occurred_at']),
    ]);
  }

  return _encodeCsv(rows);
}

/// CSV con los correos recibidos por el usuario.
///
/// Columnas: type, subject, status, locale, sent_at, created_at (ISO 8601).
///
/// Nota: `labels` se mantiene en la firma por simetría con los otros dos
/// builders (uploads/activity) y para no romper la API si en el futuro
/// queremos localizar las cabeceras. Hoy las dejamos en inglés técnico
/// porque type/subject/status son convenciones universales en mail.
Uint8List buildEmailsCsv(
  Map<String, dynamic> data,
  // ignore: avoid_unused_constructor_parameters
  PdfExportLabels labels,
) {
  final rows = <List<dynamic>>[
    [
      'type',
      'subject',
      'status',
      'locale',
      'sent_at',
      'created_at',
    ],
  ];

  final emails = _asList(data['emails_received']);
  for (final raw in emails) {
    final e = _asMap(raw);
    rows.add([
      (e['type'] as String?) ?? '',
      (e['subject'] as String?) ?? '',
      (e['status'] as String?) ?? '',
      (e['locale'] as String?) ?? '',
      _toIso(e['sent_at']),
      _toIso(e['created_at']),
    ]);
  }

  return _encodeCsv(rows);
}

// ─────────────────────────────────────────────────────────────────────
// Helpers internos
// ─────────────────────────────────────────────────────────────────────

/// Serializa filas a CSV con escaping correcto, las codifica a UTF-8 y
/// añade BOM (`﻿`) al principio para que Excel respete la
/// codificación al abrir el fichero.
///
/// Usamos `\r\n` como `lineDelimiter` (RFC 4180); compatible con Excel y
/// herramientas modernas (LibreOffice, Sheets, awk). La separación es ','
/// — Excel detecta el separador a partir del BOM + heurísticas.
///
/// `csv: ^8` añade el BOM nativamente con `addBom: true` (devuelve un
/// String que ya empieza por `﻿`); convertimos a bytes UTF-8 y eso
/// produce los 3 bytes `EF BB BF` esperados al principio del fichero.
final _csv = Csv(addBom: true);

Uint8List _encodeCsv(List<List<dynamic>> rows) {
  final csv = _csv.encode(rows);
  return Uint8List.fromList(utf8.encode(csv));
}

/// Convierte cualquier valor de fecha (`String` ISO desde Postgres o
/// `DateTime`) a ISO 8601 con offset. Si la fecha es nula o no parseable,
/// devuelve cadena vacía (no `null` — los CSVs no tienen concepto de
/// null y un campo vacío es la convención).
String _toIso(Object? raw) {
  if (raw == null) return '';
  if (raw is DateTime) return raw.toIso8601String();
  final s = raw.toString();
  final dt = DateTime.tryParse(s);
  if (dt == null) return s; // si no parsea, devuelve el string original.
  return dt.toIso8601String();
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  return const {};
}

List<dynamic> _asList(Object? raw) {
  if (raw is List) return raw;
  return const [];
}
