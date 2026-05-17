import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/status/domain/incident.dart';

Incident _make({
  IncidentStatus status = IncidentStatus.investigating,
  IncidentSeverity severity = IncidentSeverity.minor,
  bool published = true,
  DateTime? resolvedAt,
  List<String> components = const [],
}) {
  return Incident(
    id: '1',
    title: 't',
    body: '',
    status: status,
    severity: severity,
    components: components,
    startedAt: DateTime.utc(2026, 5, 1, 10),
    resolvedAt: resolvedAt,
    published: published,
    createdAt: DateTime.utc(2026, 5, 1, 10),
    updatedAt: DateTime.utc(2026, 5, 1, 10),
  );
}

void main() {
  group('Incident.fromMap', () {
    test('parses a published active critical incident', () {
      final i = Incident.fromMap(const {
        'id': '11111111-1111-1111-1111-111111111111',
        'title': 'Login outage in EU',
        'body': 'Investigating.',
        'status': 'investigating',
        'severity': 'critical',
        'components': ['auth', 'api'],
        'started_at': '2026-05-15T10:00:00Z',
        'resolved_at': null,
        'published': true,
        'created_at': '2026-05-15T10:00:00Z',
        'updated_at': '2026-05-15T10:00:00Z',
      });
      expect(i.title, 'Login outage in EU');
      expect(i.severity, IncidentSeverity.critical);
      expect(i.status, IncidentStatus.investigating);
      expect(i.components, ['auth', 'api']);
      expect(i.isActive, isTrue);
      expect(i.warrantsBanner, isTrue);
    });

    test('resolved incident is not active and does NOT warrant banner', () {
      final i = _make(
        status: IncidentStatus.resolved,
        severity: IncidentSeverity.critical,
        resolvedAt: DateTime.utc(2026, 5, 1, 11),
      );
      expect(i.isResolved, isTrue);
      expect(i.isActive, isFalse);
      expect(i.warrantsBanner, isFalse);
    });

    test('minor active does NOT warrant banner', () {
      final i = _make(
        status: IncidentStatus.identified,
        severity: IncidentSeverity.minor,
      );
      expect(i.isActive, isTrue);
      expect(i.warrantsBanner, isFalse);
    });

    test('major / critical / maintenance active warrant banner', () {
      for (final sev in [
        IncidentSeverity.major,
        IncidentSeverity.critical,
        IncidentSeverity.maintenance,
      ]) {
        final i = _make(severity: sev);
        expect(i.warrantsBanner, isTrue, reason: '$sev should warrant banner');
      }
    });

    test('unknown status string defaults to investigating', () {
      final i = Incident.fromMap(const {
        'id': '1',
        'title': 't',
        'body': '',
        'status': 'banana',
        'severity': 'minor',
        'components': <String>[],
        'started_at': '2026-05-15T10:00:00Z',
        'published': true,
        'created_at': '2026-05-15T10:00:00Z',
        'updated_at': '2026-05-15T10:00:00Z',
      });
      expect(i.status, IncidentStatus.investigating);
    });
  });

  group('computeOverallStatus', () {
    test('empty list = operational', () {
      expect(computeOverallStatus(const []), OverallStatus.operational);
    });

    test('only minor active = degraded', () {
      expect(
        computeOverallStatus([_make(severity: IncidentSeverity.minor)]),
        OverallStatus.degraded,
      );
    });

    test('major active = partial outage', () {
      expect(
        computeOverallStatus([_make(severity: IncidentSeverity.major)]),
        OverallStatus.partialOutage,
      );
    });

    test('critical active = major outage (beats everything)', () {
      expect(
        computeOverallStatus([
          _make(severity: IncidentSeverity.minor),
          _make(severity: IncidentSeverity.major),
          _make(severity: IncidentSeverity.critical),
          _make(severity: IncidentSeverity.maintenance),
        ]),
        OverallStatus.majorOutage,
      );
    });

    test('major beats maintenance', () {
      expect(
        computeOverallStatus([
          _make(severity: IncidentSeverity.maintenance),
          _make(severity: IncidentSeverity.major),
        ]),
        OverallStatus.partialOutage,
      );
    });

    test('maintenance beats minor', () {
      expect(
        computeOverallStatus([
          _make(severity: IncidentSeverity.minor),
          _make(severity: IncidentSeverity.maintenance),
        ]),
        OverallStatus.maintenance,
      );
    });

    test('resolved incidents are ignored', () {
      expect(
        computeOverallStatus([
          _make(
            status: IncidentStatus.resolved,
            severity: IncidentSeverity.critical,
            resolvedAt: DateTime.utc(2026, 5, 1, 11),
          ),
          _make(severity: IncidentSeverity.minor),
        ]),
        OverallStatus.degraded,
      );
    });
  });

  group('db round-trip helpers', () {
    test('incidentStatusToDb is bijection with parsing', () {
      for (final s in IncidentStatus.values) {
        final round = Incident.fromMap({
          'id': '1',
          'title': 't',
          'body': '',
          'status': incidentStatusToDb(s),
          'severity': 'minor',
          'started_at': '2026-05-01T10:00:00Z',
          'published': true,
          'created_at': '2026-05-01T10:00:00Z',
          'updated_at': '2026-05-01T10:00:00Z',
        }).status;
        expect(round, s);
      }
    });

    test('incidentSeverityToDb is bijection with parsing', () {
      for (final s in IncidentSeverity.values) {
        final round = Incident.fromMap({
          'id': '1',
          'title': 't',
          'body': '',
          'status': 'investigating',
          'severity': incidentSeverityToDb(s),
          'started_at': '2026-05-01T10:00:00Z',
          'published': true,
          'created_at': '2026-05-01T10:00:00Z',
          'updated_at': '2026-05-01T10:00:00Z',
        }).severity;
        expect(round, s);
      }
    });
  });
}
