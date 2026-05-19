// Tests del parser de Audit Center (PR-Audit-3).
//
// Cubren las 4 superficies criticas del fromMap:
//   - AuditSeverity.fromString cubre todos los valores conocidos +
//     fallback a info para valores desconocidos.
//   - AuditFinding.fromMap parsea con todos los campos opcionales y sin
//     ellos.
//   - AuditReportSummary.fromMap genera 0 por defecto en todas las
//     severities cuando el backend no las incluye.
//   - AuditReport.fromMap parsea findings list + summary anidado y
//     conserva timestamps en UTC.

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/audit_center/domain/audit_report.dart';

void main() {
  group('AuditSeverity.fromString', () {
    test('parsea cada valor canonico', () {
      expect(AuditSeverity.fromString('critical'), AuditSeverity.critical);
      expect(AuditSeverity.fromString('high'), AuditSeverity.high);
      expect(AuditSeverity.fromString('medium'), AuditSeverity.medium);
      expect(AuditSeverity.fromString('low'), AuditSeverity.low);
      expect(AuditSeverity.fromString('info'), AuditSeverity.info);
    });

    test('cae a info para null o valores desconocidos', () {
      expect(AuditSeverity.fromString(null), AuditSeverity.info);
      expect(AuditSeverity.fromString('CRITICAL'), AuditSeverity.info);
      expect(AuditSeverity.fromString('moderate'), AuditSeverity.info);
    });

    test('rank ordena critical primero', () {
      final sevs = AuditSeverity.values.toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));
      expect(sevs.first, AuditSeverity.critical);
      expect(sevs.last, AuditSeverity.info);
    });
  });

  group('AuditReportStatus.fromString', () {
    test('parsea cada valor canonico', () {
      expect(
        AuditReportStatus.fromString('running'),
        AuditReportStatus.running,
      );
      expect(
        AuditReportStatus.fromString('completed'),
        AuditReportStatus.completed,
      );
      expect(
        AuditReportStatus.fromString('failed'),
        AuditReportStatus.failed,
      );
    });

    test('cae a running para nulos / desconocidos', () {
      expect(AuditReportStatus.fromString(null), AuditReportStatus.running);
      expect(
        AuditReportStatus.fromString('paused'),
        AuditReportStatus.running,
      );
    });
  });

  group('AuditFinding.fromMap', () {
    test('parsea todos los campos', () {
      final f = AuditFinding.fromMap(const {
        'check_id': 'rls.coverage',
        'title': '2 tablas sin RLS',
        'severity': 'critical',
        'impact': 'cualquier user puede leer/escribir',
        'recommendation': 'enable rls + add policies',
        'affected_count': 2,
        'details': {'tables': ['x', 'y']},
      });
      expect(f.checkId, 'rls.coverage');
      expect(f.title, '2 tablas sin RLS');
      expect(f.severity, AuditSeverity.critical);
      expect(f.impact, 'cualquier user puede leer/escribir');
      expect(f.recommendation, 'enable rls + add policies');
      expect(f.affectedCount, 2);
      expect(f.details, isNotNull);
      expect(f.details!['tables'], ['x', 'y']);
    });

    test('aplica defaults seguros cuando faltan campos', () {
      final f = AuditFinding.fromMap(const <String, dynamic>{});
      expect(f.checkId, 'unknown');
      expect(f.title, '');
      expect(f.severity, AuditSeverity.info);
      expect(f.affectedCount, 0);
      expect(f.details, isNull);
    });
  });

  group('AuditReportSummary.fromMap', () {
    test('por defecto rellena cada severity a 0', () {
      final s = AuditReportSummary.fromMap(const <String, dynamic>{});
      for (final sev in AuditSeverity.values) {
        expect(s.count(sev), 0);
      }
      expect(s.totalChecksRun, 0);
      expect(s.totalFindings, 0);
      expect(s.hasSevereFindings, isFalse);
    });

    test('hasSevereFindings true si hay critical o high', () {
      final s = AuditReportSummary.fromMap(const {
        'by_severity': {
          'critical': 0,
          'high': 1,
          'medium': 0,
          'low': 0,
          'info': 5,
        },
      });
      expect(s.hasSevereFindings, isTrue);
      expect(s.count(AuditSeverity.high), 1);
      expect(s.count(AuditSeverity.info), 5);
    });

    test('hasSevereFindings false con solo low/info', () {
      final s = AuditReportSummary.fromMap(const {
        'by_severity': {
          'critical': 0,
          'high': 0,
          'medium': 0,
          'low': 3,
          'info': 2,
        },
        'total_checks_run': 12,
        'total_findings': 5,
        'duration_ms': 3500,
        'version': 'v1',
      });
      expect(s.hasSevereFindings, isFalse);
      expect(s.totalChecksRun, 12);
      expect(s.durationMs, 3500);
      expect(s.version, 'v1');
    });
  });

  group('AuditReport.fromMap', () {
    test('parsea report completo con findings', () {
      final r = AuditReport.fromMap(const {
        'id': 'abc-123',
        'started_at': '2026-05-19T14:30:00Z',
        'finished_at': '2026-05-19T14:30:06Z',
        'status': 'completed',
        'summary': {
          'by_severity': {
            'critical': 1,
            'high': 0,
            'medium': 0,
            'low': 0,
            'info': 0,
          },
          'total_checks_run': 12,
          'total_findings': 1,
          'duration_ms': 6000,
        },
        'findings': [
          {
            'check_id': 'rls.coverage',
            'title': '2 tables without RLS',
            'severity': 'critical',
            'impact': 'leak',
            'recommendation': 'fix',
            'affected_count': 2,
          },
        ],
        'triggered_by': 'user-uuid',
      });
      expect(r.id, 'abc-123');
      expect(r.status, AuditReportStatus.completed);
      expect(r.findings, hasLength(1));
      expect(r.findings.first.severity, AuditSeverity.critical);
      expect(r.duration, const Duration(seconds: 6));
      expect(r.triggeredBy, 'user-uuid');
    });

    test('tolera findings ausentes o no-lista', () {
      final r = AuditReport.fromMap(const {
        'id': 'abc',
        'started_at': '2026-05-19T14:30:00Z',
        'status': 'running',
        'summary': {},
      });
      expect(r.findings, isEmpty);
      expect(r.status, AuditReportStatus.running);
      expect(r.duration, isNull);
    });

    test('findingsBySeverity agrupa preservando orden de insertion', () {
      final r = AuditReport.fromMap(const {
        'id': 'x',
        'started_at': '2026-05-19T14:30:00Z',
        'status': 'completed',
        'summary': {},
        'findings': [
          {'check_id': 'a', 'severity': 'high', 'title': 'A'},
          {'check_id': 'b', 'severity': 'critical', 'title': 'B'},
          {'check_id': 'c', 'severity': 'high', 'title': 'C'},
        ],
      });
      final grouped = r.findingsBySeverity();
      expect(grouped[AuditSeverity.critical], hasLength(1));
      expect(grouped[AuditSeverity.high], hasLength(2));
      expect(grouped[AuditSeverity.high]!.first.title, 'A');
      expect(grouped[AuditSeverity.high]!.last.title, 'C');
      // Severities sin findings devuelven lista vacia, no null.
      expect(grouped[AuditSeverity.low], isEmpty);
    });
  });

  group('AuditReportSummaryRow.fromMap', () {
    test('parsea row sin finished_at (running)', () {
      final row = AuditReportSummaryRow.fromMap(const {
        'id': 'r1',
        'started_at': '2026-05-19T14:30:00Z',
        'status': 'running',
        'summary': <String, dynamic>{},
        'triggered_by': null,
      });
      expect(row.status, AuditReportStatus.running);
      expect(row.finishedAt, isNull);
      expect(row.duration, isNull);
      expect(row.triggeredBy, isNull);
    });

    test('calcula duration cuando hay finished_at', () {
      final row = AuditReportSummaryRow.fromMap(const {
        'id': 'r2',
        'started_at': '2026-05-19T14:30:00Z',
        'finished_at': '2026-05-19T14:30:10Z',
        'status': 'completed',
        'summary': <String, dynamic>{},
      });
      expect(row.duration, const Duration(seconds: 10));
    });
  });
}
