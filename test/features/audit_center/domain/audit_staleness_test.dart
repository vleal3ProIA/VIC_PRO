// Tests del helper staleness del Audit Center (PR-Audit-4).
//
// Cubrimos las 5 ramas del decision tree de evaluateAuditStaleness:
//   1. lista vacia                  -> noReports
//   2. running                      -> running
//   3. completed < 7d               -> fresh
//   4. completed >= 7d              -> stale (too_old)
//   5. failed                       -> stale (last_failed)
//
// `now` se inyecta para que los tests sean deterministicos -- sin esto,
// el threshold de 7d dependeria del reloj del CI.

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/audit_center/domain/audit_report.dart';
import 'package:myapp/features/audit_center/domain/audit_staleness.dart';

AuditReportSummaryRow _row({
  required DateTime startedAt,
  required AuditReportStatus status,
  DateTime? finishedAt,
}) {
  return AuditReportSummaryRow(
    id: 'fake',
    startedAt: startedAt,
    finishedAt: finishedAt,
    status: status,
    summary: AuditReportSummary.empty(),
  );
}

void main() {
  // Punto de referencia fijo para todos los tests.
  final now = DateTime.utc(2026, 5, 19, 12);

  group('evaluateAuditStaleness', () {
    test('lista vacia -> noReports (no stale)', () {
      final result = evaluateAuditStaleness(const [], now: now);
      expect(result.isStale, isFalse);
      expect(result.reason, 'empty');
      expect(result.daysSinceLast, isNull);
    });

    test('latest running -> running (no stale, mostrar polling)', () {
      final result = evaluateAuditStaleness(
        [
          _row(
            startedAt: now.subtract(const Duration(hours: 1)),
            status: AuditReportStatus.running,
          ),
        ],
        now: now,
      );
      expect(result.isStale, isFalse);
      expect(result.reason, 'audit_running');
    });

    test('completed < 7d -> fresh', () {
      final result = evaluateAuditStaleness(
        [
          _row(
            startedAt: now.subtract(const Duration(days: 3)),
            finishedAt: now.subtract(const Duration(days: 3, minutes: -1)),
            status: AuditReportStatus.completed,
          ),
        ],
        now: now,
      );
      expect(result.isStale, isFalse);
      expect(result.reason, 'fresh');
      expect(result.daysSinceLast, 3);
    });

    test('completed exactamente 7d -> stale (umbral inclusivo)', () {
      final result = evaluateAuditStaleness(
        [
          _row(
            startedAt: now.subtract(const Duration(days: 7)),
            finishedAt: now.subtract(const Duration(days: 7, minutes: -1)),
            status: AuditReportStatus.completed,
          ),
        ],
        now: now,
      );
      expect(result.isStale, isTrue);
      expect(result.reason, 'too_old');
      expect(result.daysSinceLast, 7);
    });

    test('completed > 7d -> stale (too_old)', () {
      final result = evaluateAuditStaleness(
        [
          _row(
            startedAt: now.subtract(const Duration(days: 30)),
            finishedAt: now.subtract(const Duration(days: 30, minutes: -1)),
            status: AuditReportStatus.completed,
          ),
        ],
        now: now,
      );
      expect(result.isStale, isTrue);
      expect(result.reason, 'too_old');
      expect(result.daysSinceLast, 30);
    });

    test('latest failed (cualquier edad) -> stale (last_failed)', () {
      final result = evaluateAuditStaleness(
        [
          _row(
            startedAt: now.subtract(const Duration(hours: 2)),
            finishedAt: now.subtract(const Duration(hours: 1)),
            status: AuditReportStatus.failed,
          ),
          // Aunque haya un completed fresco antes, el "latest" es el
          // failed -- staleness debe usar el primero de la lista.
          _row(
            startedAt: now.subtract(const Duration(days: 1)),
            finishedAt: now.subtract(const Duration(days: 1, minutes: -1)),
            status: AuditReportStatus.completed,
          ),
        ],
        now: now,
      );
      expect(result.isStale, isTrue);
      expect(result.reason, 'last_failed');
      expect(result.daysSinceLast, 0);
    });

    test('threshold configurable: a 14d, 10d es fresh', () {
      final result = evaluateAuditStaleness(
        [
          _row(
            startedAt: now.subtract(const Duration(days: 10)),
            finishedAt: now.subtract(const Duration(days: 10, minutes: -1)),
            status: AuditReportStatus.completed,
          ),
        ],
        now: now,
        staleThresholdDays: 14,
      );
      expect(result.isStale, isFalse);
      expect(result.daysSinceLast, 10);
    });
  });
}
