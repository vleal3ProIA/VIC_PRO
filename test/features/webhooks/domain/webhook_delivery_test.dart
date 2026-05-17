import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/webhooks/domain/webhook_delivery.dart';

void main() {
  group('WebhookDelivery.fromMap', () {
    test('parses a successful delivery', () {
      final d = WebhookDelivery.fromMap(const {
        'id': 'd1',
        'endpoint_id': 'e1',
        'event_type': 'user.created',
        'status': 'success',
        'attempt': 1,
        'http_status': 200,
        'response_body': '{"ok":true}',
        'error': null,
        'next_retry_at': null,
        'created_at': '2026-05-01T10:00:00Z',
        'delivered_at': '2026-05-01T10:00:01Z',
        'failed_at': null,
      });
      expect(d.eventType, 'user.created');
      expect(d.status, WebhookDeliveryStatus.success);
      expect(d.httpStatus, 200);
      expect(d.deliveredAt, isNotNull);
      expect(d.failedAt, isNull);
    });

    test('parses a failed delivery with error', () {
      final d = WebhookDelivery.fromMap(const {
        'id': 'd1',
        'endpoint_id': 'e1',
        'event_type': 'invoice.paid',
        'status': 'failed',
        'attempt': 5,
        'http_status': 500,
        'error': 'http_500',
        'created_at': '2026-05-01T10:00:00Z',
        'failed_at': '2026-05-02T10:00:00Z',
      });
      expect(d.status, WebhookDeliveryStatus.failed);
      expect(d.attempt, 5);
      expect(d.error, 'http_500');
      expect(d.failedAt, isNotNull);
    });

    test('parses a retry delivery with next_retry_at', () {
      final d = WebhookDelivery.fromMap(const {
        'id': 'd1',
        'endpoint_id': 'e1',
        'event_type': 'subscription.updated',
        'status': 'retry',
        'attempt': 2,
        'http_status': 503,
        'next_retry_at': '2026-05-01T11:00:00Z',
        'created_at': '2026-05-01T10:00:00Z',
      });
      expect(d.status, WebhookDeliveryStatus.retry);
      expect(d.nextRetryAt, isNotNull);
      expect(d.deliveredAt, isNull);
      expect(d.failedAt, isNull);
    });

    test('defaults attempt to 1 when missing', () {
      final d = WebhookDelivery.fromMap(const {
        'id': 'd1',
        'endpoint_id': 'e1',
        'event_type': 'test.ping',
        'status': 'pending',
        'created_at': '2026-05-01T10:00:00Z',
      });
      expect(d.attempt, 1);
      expect(d.status, WebhookDeliveryStatus.pending);
    });

    test('unknown status defaults to pending', () {
      final d = WebhookDelivery.fromMap(const {
        'id': 'd1',
        'endpoint_id': 'e1',
        'event_type': 'x',
        'status': 'banana',
        'created_at': '2026-05-01T10:00:00Z',
      });
      expect(d.status, WebhookDeliveryStatus.pending);
    });
  });
}
