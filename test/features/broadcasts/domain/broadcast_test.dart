import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/broadcasts/domain/broadcast.dart';

void main() {
  group('Broadcast.fromMap', () {
    test('parses a sending broadcast with all fields', () {
      final b = Broadcast.fromMap(const {
        'id': '11111111-1111-1111-1111-111111111111',
        'subject': 'Big announcement',
        'body_html': '<p>Hello!</p>',
        'target_type': 'plan',
        'target_value': {'slug': 'pro'},
        'status': 'sending',
        'recipients_total': 200,
        'sent_count': 50,
        'failed_count': 2,
        'processed_offset': 52,
        'created_by': 'admin-uuid',
        'created_at': '2026-05-15T10:00:00Z',
        'updated_at': '2026-05-15T10:05:00Z',
        'started_at': '2026-05-15T10:01:00Z',
      });
      expect(b.subject, 'Big announcement');
      expect(b.targetType, BroadcastTargetType.plan);
      expect(b.targetValue['slug'], 'pro');
      expect(b.status, BroadcastStatus.sending);
      expect(b.recipientsTotal, 200);
      expect(b.sentCount, 50);
      expect(b.failedCount, 2);
      expect(b.processedOffset, 52);
      expect(b.isInFlight, isTrue);
      expect(b.isFinished, isFalse);
      expect(b.progressFraction, closeTo(0.26, 0.001));
    });

    test('progressFraction is 0 when total is 0', () {
      final b = Broadcast.fromMap(const {
        'id': '1',
        'subject': 's',
        'body_html': 'b',
        'target_type': 'all',
        'status': 'draft',
        'recipients_total': 0,
        'sent_count': 0,
        'failed_count': 0,
        'processed_offset': 0,
        'created_by': 'u',
        'created_at': '2026-05-15T10:00:00Z',
        'updated_at': '2026-05-15T10:00:00Z',
      });
      expect(b.progressFraction, 0.0);
    });

    test('progressFraction clamps to 1.0 max', () {
      // Edge case: processed_offset > recipients_total (shouldnt happen
      // but defensive).
      final b = Broadcast.fromMap(const {
        'id': '1',
        'subject': 's',
        'body_html': 'b',
        'target_type': 'all',
        'status': 'sent',
        'recipients_total': 100,
        'sent_count': 100,
        'failed_count': 0,
        'processed_offset': 105,
        'created_by': 'u',
        'created_at': '2026-05-15T10:00:00Z',
        'updated_at': '2026-05-15T10:00:00Z',
      });
      expect(b.progressFraction, 1.0);
    });

    test('parses each target type', () {
      BroadcastTargetType parse(String s) =>
          Broadcast.fromMap({
            'id': '1',
            'subject': 's',
            'body_html': 'b',
            'target_type': s,
            'status': 'draft',
            'recipients_total': 0,
            'sent_count': 0,
            'failed_count': 0,
            'processed_offset': 0,
            'created_by': 'u',
            'created_at': '2026-05-15T10:00:00Z',
            'updated_at': '2026-05-15T10:00:00Z',
          }).targetType;
      expect(parse('all'), BroadcastTargetType.all);
      expect(parse('plan'), BroadcastTargetType.plan);
      expect(parse('language'), BroadcastTargetType.language);
      expect(parse('status'), BroadcastTargetType.status);
      expect(parse('unknown'), BroadcastTargetType.all);
    });

    test('parses each status', () {
      BroadcastStatus parse(String s) =>
          Broadcast.fromMap({
            'id': '1',
            'subject': 's',
            'body_html': 'b',
            'target_type': 'all',
            'status': s,
            'recipients_total': 0,
            'sent_count': 0,
            'failed_count': 0,
            'processed_offset': 0,
            'created_by': 'u',
            'created_at': '2026-05-15T10:00:00Z',
            'updated_at': '2026-05-15T10:00:00Z',
          }).status;
      expect(parse('draft'), BroadcastStatus.draft);
      expect(parse('sending'), BroadcastStatus.sending);
      expect(parse('sent'), BroadcastStatus.sent);
      expect(parse('failed'), BroadcastStatus.failed);
      expect(parse('banana'), BroadcastStatus.draft);
    });

    test('isFinished true for sent and failed', () {
      Broadcast make(String status) => Broadcast.fromMap({
            'id': '1',
            'subject': 's',
            'body_html': 'b',
            'target_type': 'all',
            'status': status,
            'recipients_total': 0,
            'sent_count': 0,
            'failed_count': 0,
            'processed_offset': 0,
            'created_by': 'u',
            'created_at': '2026-05-15T10:00:00Z',
            'updated_at': '2026-05-15T10:00:00Z',
          });
      expect(make('sent').isFinished, isTrue);
      expect(make('failed').isFinished, isTrue);
      expect(make('sending').isFinished, isFalse);
      expect(make('draft').isFinished, isFalse);
    });
  });

  group('BroadcastEstimate', () {
    test('parses count and by_locale map', () {
      final e = BroadcastEstimate.fromMap(const {
        'count': 150,
        'by_locale': {'es': 80, 'en': 50, 'fr': 20},
      });
      expect(e.count, 150);
      expect(e.byLocale['es'], 80);
      expect(e.byLocale['en'], 50);
      expect(e.byLocale, hasLength(3));
    });

    test('handles missing by_locale', () {
      final e = BroadcastEstimate.fromMap(const {'count': 0});
      expect(e.count, 0);
      expect(e.byLocale, isEmpty);
    });
  });

  group('BroadcastTargetType', () {
    test('dbValue matches enum name', () {
      expect(BroadcastTargetType.all.dbValue, 'all');
      expect(BroadcastTargetType.plan.dbValue, 'plan');
      expect(BroadcastTargetType.language.dbValue, 'language');
      expect(BroadcastTargetType.status.dbValue, 'status');
    });
  });
}
