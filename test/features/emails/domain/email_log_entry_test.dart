import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/emails/domain/email_log_entry.dart';

void main() {
  group('EmailLogEntry.fromMap', () {
    test('parses a fully populated sent entry', () {
      final e = EmailLogEntry.fromMap(const {
        'id': '11111111-1111-1111-1111-111111111111',
        'type': 'plan_changed',
        'to_email': 'user@example.com',
        'to_user_id': '22222222-2222-2222-2222-222222222222',
        'locale': 'es',
        'subject': 'Tu plan ha cambiado',
        'status': 'sent',
        'error': null,
        'provider': 'smtp',
        'meta': {'plan_id': 'pro'},
        'sent_at': '2026-05-15T10:00:01Z',
        'created_at': '2026-05-15T10:00:00Z',
      });
      expect(e.type, 'plan_changed');
      expect(e.toEmail, 'user@example.com');
      expect(e.toUserId, '22222222-2222-2222-2222-222222222222');
      expect(e.locale, 'es');
      expect(e.status, EmailLogStatus.sent);
      expect(e.isSent, isTrue);
      expect(e.isFailed, isFalse);
      expect(e.meta['plan_id'], 'pro');
      expect(e.sentAt!.year, 2026);
    });

    test('parses a failed entry', () {
      final e = EmailLogEntry.fromMap(const {
        'id': '1',
        'type': 'recovery',
        'to_email': 'x@x.com',
        'locale': 'en',
        'subject': 'Reset your password',
        'status': 'failed',
        'error': 'smtp_timeout',
        'provider': 'smtp',
        'meta': {},
        'created_at': '2026-05-15T10:00:00Z',
      });
      expect(e.status, EmailLogStatus.failed);
      expect(e.isFailed, isTrue);
      expect(e.error, 'smtp_timeout');
      expect(e.sentAt, isNull);
    });

    test('parses a queued entry (still in-flight)', () {
      final e = EmailLogEntry.fromMap(const {
        'id': '1',
        'type': 'signup',
        'to_email': 'x@x.com',
        'locale': 'en',
        'subject': 'Confirm your email',
        'status': 'queued',
        'provider': 'smtp',
        'meta': {},
        'created_at': '2026-05-15T10:00:00Z',
      });
      expect(e.status, EmailLogStatus.queued);
      expect(e.isSent, isFalse);
      expect(e.isFailed, isFalse);
    });

    test('unknown status defaults to queued', () {
      final e = EmailLogEntry.fromMap(const {
        'id': '1',
        'type': 'test',
        'to_email': 'x@x.com',
        'locale': 'en',
        'subject': 's',
        'status': 'banana',
        'provider': 'smtp',
        'meta': {},
        'created_at': '2026-05-15T10:00:00Z',
      });
      expect(e.status, EmailLogStatus.queued);
    });

    test('defaults locale/provider/meta when missing', () {
      final e = EmailLogEntry.fromMap(const {
        'id': '1',
        'type': 'test',
        'to_email': 'x@x.com',
        'subject': 's',
        'status': 'sent',
        'created_at': '2026-05-15T10:00:00Z',
      });
      expect(e.locale, 'en');
      expect(e.provider, 'smtp');
      expect(e.meta, isEmpty);
    });
  });
}
