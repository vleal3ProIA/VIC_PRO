import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/webhooks/domain/webhook_endpoint.dart';

void main() {
  group('WebhookEndpoint.fromMap', () {
    test('parses an active wildcard endpoint', () {
      final e = WebhookEndpoint.fromMap(const {
        'id': '11111111-1111-1111-1111-111111111111',
        'user_id': 'u1',
        'tenant_id': null,
        'url': 'https://example.com/hooks',
        'description': 'Production',
        'events': ['*'],
        'active': true,
        'consecutive_failures': 0,
        'disabled_reason': null,
        'created_at': '2026-05-01T10:00:00Z',
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(e.url, 'https://example.com/hooks');
      expect(e.isWildcard, isTrue);
      expect(e.active, isTrue);
      expect(e.autoDisabled, isFalse);
      expect(e.hasRecentFailures, isFalse);
      expect(e.secret, isNull);
    });

    test('defaults events to [*] when missing', () {
      final e = WebhookEndpoint.fromMap(const {
        'id': '1',
        'user_id': 'u1',
        'url': 'https://x.com/h',
        'active': true,
        'created_at': '2026-05-01T10:00:00Z',
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(e.events, ['*']);
      expect(e.isWildcard, isTrue);
    });

    test('parses raw secret from create response', () {
      final e = WebhookEndpoint.fromMap(const {
        'id': '1',
        'user_id': 'u1',
        'url': 'https://x.com/h',
        'events': ['user.created'],
        'active': true,
        'created_at': '2026-05-01T10:00:00Z',
        'updated_at': '2026-05-01T10:00:00Z',
        'secret': 'whsec_abc123',
      });
      expect(e.secret, 'whsec_abc123');
      expect(e.isWildcard, isFalse);
    });
  });

  group('state flags', () {
    test('autoDisabled when disabled_reason = too_many_failures', () {
      final e = WebhookEndpoint.fromMap(const {
        'id': '1',
        'user_id': 'u1',
        'url': 'https://x.com/h',
        'active': false,
        'consecutive_failures': 12,
        'disabled_reason': 'too_many_failures',
        'created_at': '2026-05-01T10:00:00Z',
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(e.autoDisabled, isTrue);
      expect(e.hasRecentFailures, isTrue);
      expect(e.active, isFalse);
    });

    test('NOT autoDisabled when manually paused', () {
      final e = WebhookEndpoint.fromMap(const {
        'id': '1',
        'user_id': 'u1',
        'url': 'https://x.com/h',
        'active': false,
        'disabled_reason': 'manual',
        'created_at': '2026-05-01T10:00:00Z',
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(e.autoDisabled, isFalse);
      expect(e.active, isFalse);
    });

    test('hasRecentFailures is true when consecutive > 0', () {
      final e = WebhookEndpoint.fromMap(const {
        'id': '1',
        'user_id': 'u1',
        'url': 'https://x.com/h',
        'active': true,
        'consecutive_failures': 3,
        'created_at': '2026-05-01T10:00:00Z',
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(e.hasRecentFailures, isTrue);
      expect(e.active, isTrue);
    });
  });
}
