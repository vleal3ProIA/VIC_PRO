// Tests del renderer TXT del Audit Center (PR-Audit-3).
//
// Validamos:
//   - Header con id, timestamps, status, conteos por severity.
//   - Cada bloque de severity aparece (incluso "(none)" para vacios).
//   - Findings incluyen check_id, impact, recommendation, details JSON.
//   - Las secciones se ordenan critical -> info.
//   - El renderer es puro -- no requiere BuildContext ni package:web.

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/audit_center/domain/audit_report.dart';
import 'package:myapp/features/audit_center/presentation/util/audit_txt_export.dart';

AuditReport _sampleReport() {
  return AuditReport.fromMap(const {
    'id': 'aaaaaaaa-1111-2222-3333-444444444444',
    'started_at': '2026-05-19T14:30:00Z',
    'finished_at': '2026-05-19T14:30:08Z',
    'status': 'completed',
    'summary': {
      'by_severity': {
        'critical': 1,
        'high': 1,
        'medium': 0,
        'low': 1,
        'info': 0,
      },
      'total_checks_run': 12,
      'total_findings': 3,
      'duration_ms': 8000,
      'version': 'v1',
    },
    'findings': [
      {
        'check_id': 'rls.coverage',
        'title': '2 tables without RLS',
        'severity': 'critical',
        'impact': 'unauthenticated read/write',
        'recommendation': 'enable rls + add policies',
        'affected_count': 2,
        'details': {'tables': ['x', 'y']},
      },
      {
        'check_id': 'auth.mfa_admin_coverage',
        'title': 'admin sin MFA',
        'severity': 'high',
        'impact': 'compromise point',
        'recommendation': 'force MFA enrollment',
        'affected_count': 1,
      },
      {
        'check_id': 'tokens.unused_long_lived',
        'title': '3 stale PATs',
        'severity': 'low',
        'impact': 'credential leak risk',
        'recommendation': 'rotate or revoke',
        'affected_count': 3,
      },
    ],
    'triggered_by': 'admin-uuid',
  });
}

void main() {
  group('renderAuditReportAsTxt', () {
    test('incluye id, status y meta del summary en el header', () {
      final txt = renderAuditReportAsTxt(_sampleReport());

      expect(txt, contains('Audit Report aaaaaaaa-1111-2222-3333-444444444444'));
      expect(txt, contains('Status:   completed'));
      expect(txt, contains('Total findings: 3'));
      expect(txt, contains('Checks run:     12'));
      expect(txt, contains('Duration:       8000ms'));
      expect(txt, contains('Version:        v1'));
      expect(txt, contains('Triggered by: admin-uuid'));
    });

    test('incluye una seccion por severity en orden', () {
      final txt = renderAuditReportAsTxt(_sampleReport());
      final critPos = txt.indexOf('Critical (1)');
      final highPos = txt.indexOf('High (1)');
      final medPos = txt.indexOf('Medium (0)');
      final lowPos = txt.indexOf('Low (1)');
      final infoPos = txt.indexOf('Info (0)');

      expect(critPos, greaterThan(-1));
      expect(highPos, greaterThan(critPos));
      expect(medPos, greaterThan(highPos));
      expect(lowPos, greaterThan(medPos));
      expect(infoPos, greaterThan(lowPos));
    });

    test('renderea "(none)" para severities sin findings', () {
      final txt = renderAuditReportAsTxt(_sampleReport());
      // Medium e Info estan vacios.
      expect(txt, contains('Medium (0)'));
      expect(txt, contains('Info (0)'));
      expect('(none)'.allMatches(txt).length, greaterThanOrEqualTo(2));
    });

    test('cada finding incluye check_id, impact, recommendation', () {
      final txt = renderAuditReportAsTxt(_sampleReport());
      expect(txt, contains('rls.coverage -- 2 tables without RLS'));
      expect(txt, contains('unauthenticated read/write'));
      expect(txt, contains('enable rls + add policies'));
      expect(txt, contains('Affected:       2'));
    });

    test('details JSON aparece indentado bajo el finding', () {
      final txt = renderAuditReportAsTxt(_sampleReport());
      expect(txt, contains('Details:'));
      expect(txt, contains('"tables"'));
      expect(txt, contains('"x"'));
    });

    test('para report running muestra "(still running)"', () {
      final running = AuditReport.fromMap(const {
        'id': 'r1',
        'started_at': '2026-05-19T14:30:00Z',
        'status': 'running',
        'summary': <String, dynamic>{},
      });
      final txt = renderAuditReportAsTxt(running);
      expect(txt, contains('(still running)'));
      expect(txt, contains('Status:   running'));
    });
  });
}
