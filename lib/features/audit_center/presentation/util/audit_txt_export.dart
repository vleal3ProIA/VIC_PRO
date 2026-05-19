// ============================================================================
// Audit Center · TXT export (PR-Audit-3)
// ----------------------------------------------------------------------------
// Renderiza un `AuditReport` como texto plano legible para incluirlo en
// tickets / emails / runbooks. Es la version "shareable" del informe
// que se ve en la UI -- mismo contenido, sin colores.
//
// **Pura**: no toca `dart:html` / `package:web` -- solo formatea strings.
// El boton de descarga real esta en `audit_txt_download.dart` (ese si
// usa `package:web`).
//
// **Formato**:
//
//   Audit Report <id>
//   ================================================================
//   Started: 2026-05-19 14:30:12
//   Finished: 2026-05-19 14:30:18 (6s)
//   Status: completed
//   Total findings: 7  (critical: 0, high: 2, medium: 3, low: 1, info: 1)
//
//   ── Critical (0) ──────────────────────────────────────────────────
//   (none)
//
//   ── High (2) ──────────────────────────────────────────────────────
//   [1] uploads.scan_errors -- 12 upload(s) with stuck virus scans
//       Impact: Files were uploaded but VirusTotal never replied. ...
//       Recommendation: 1) Check VIRUSTOTAL_API_KEY. 2) Re-scan ...
//       Affected: 12
//
//   ...
// ============================================================================

import 'dart:convert';

import '../../domain/audit_report.dart';

/// Renderiza el report como texto plano. Lo usa el boton "Download TXT"
/// del detail page (envuelto en un Blob via `package:web`).
String renderAuditReportAsTxt(AuditReport report) {
  final buf = StringBuffer();
  final separator = '=' * 72;

  buf.writeln('Audit Report ${report.id}');
  buf.writeln(separator);
  buf.writeln('Started:  ${report.startedAt.toUtc().toIso8601String()}');
  if (report.finishedAt != null) {
    final d = report.duration;
    final dLabel = d != null ? ' (${d.inSeconds}s)' : '';
    buf.writeln(
      'Finished: ${report.finishedAt!.toUtc().toIso8601String()}$dLabel',
    );
  } else {
    buf.writeln('Finished: (still running)');
  }
  buf.writeln('Status:   ${report.status.name}');
  if (report.error != null && report.error!.isNotEmpty) {
    buf.writeln('Error:    ${report.error}');
  }
  if (report.triggeredBy != null) {
    buf.writeln('Triggered by: ${report.triggeredBy}');
  }
  final counts = report.summary.bySeverity.entries
      .map((e) => '${e.key.name}: ${e.value}')
      .join(', ');
  buf.writeln(
    'Total findings: ${report.summary.totalFindings}  ($counts)',
  );
  buf.writeln('Checks run:     ${report.summary.totalChecksRun}');
  buf.writeln('Duration:       ${report.summary.durationMs}ms');
  if (report.summary.version != null) {
    buf.writeln('Version:        ${report.summary.version}');
  }
  buf.writeln();

  final grouped = report.findingsBySeverity();
  for (final sev in AuditSeverity.values) {
    final group = grouped[sev] ?? <AuditFinding>[];
    final header = _capitalize(sev.name);
    final prefix = '── $header (${group.length}) ';
    // Padding hasta 72 chars con '─' para mantener separator visual.
    final fillLen = 72 - prefix.length;
    final filler = fillLen > 0 ? '─' * fillLen : '';
    buf.writeln('$prefix$filler');
    if (group.isEmpty) {
      buf.writeln('(none)');
    } else {
      for (var i = 0; i < group.length; i++) {
        final f = group[i];
        buf.writeln('[${i + 1}] ${f.checkId} -- ${f.title}');
        if (f.impact.isNotEmpty) {
          buf.writeln('    Impact:         ${_indent(f.impact, 20)}');
        }
        if (f.recommendation.isNotEmpty) {
          buf.writeln(
            '    Recommendation: ${_indent(f.recommendation, 20)}',
          );
        }
        if (f.affectedCount > 0) {
          buf.writeln('    Affected:       ${f.affectedCount}');
        }
        if (f.details != null && f.details!.isNotEmpty) {
          final json = const JsonEncoder.withIndent('      ')
              .convert(f.details);
          buf.writeln('    Details:');
          for (final line in const LineSplitter().convert(json)) {
            buf.writeln('      $line');
          }
        }
        buf.writeln();
      }
    }
    buf.writeln();
  }

  return buf.toString();
}

/// Indenta cada salto de linea adicional con `n` espacios para que el
/// texto multi-linea quede alineado bajo la columna del label.
String _indent(String text, int n) {
  final pad = ' ' * n;
  return text.replaceAll('\n', '\n$pad');
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
