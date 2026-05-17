import 'package:meta/meta.dart';

/// Estado de un intento de delivery hacia el endpoint del cliente.
enum WebhookDeliveryStatus { pending, success, retry, failed }

WebhookDeliveryStatus _parseStatus(String? s) {
  switch (s) {
    case 'success':
      return WebhookDeliveryStatus.success;
    case 'retry':
      return WebhookDeliveryStatus.retry;
    case 'failed':
      return WebhookDeliveryStatus.failed;
    default:
      return WebhookDeliveryStatus.pending;
  }
}

/// Log de un intento de POST a un endpoint. Cada vez que el
/// dispatcher envía un evento, escribe una fila aquí con el resultado.
@immutable
class WebhookDelivery {
  const WebhookDelivery({
    required this.id,
    required this.endpointId,
    required this.eventType,
    required this.status,
    required this.attempt,
    required this.createdAt,
    this.httpStatus,
    this.responseBody,
    this.error,
    this.nextRetryAt,
    this.deliveredAt,
    this.failedAt,
  });

  factory WebhookDelivery.fromMap(Map<String, dynamic> m) {
    return WebhookDelivery(
      id: m['id'] as String,
      endpointId: m['endpoint_id'] as String,
      eventType: m['event_type'] as String,
      status: _parseStatus(m['status'] as String?),
      attempt: (m['attempt'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.parse(m['created_at'] as String),
      httpStatus: (m['http_status'] as num?)?.toInt(),
      responseBody: m['response_body'] as String?,
      error: m['error'] as String?,
      nextRetryAt: m['next_retry_at'] != null
          ? DateTime.parse(m['next_retry_at'] as String)
          : null,
      deliveredAt: m['delivered_at'] != null
          ? DateTime.parse(m['delivered_at'] as String)
          : null,
      failedAt: m['failed_at'] != null
          ? DateTime.parse(m['failed_at'] as String)
          : null,
    );
  }

  final String id;
  final String endpointId;
  final String eventType;
  final WebhookDeliveryStatus status;
  final int attempt;
  final DateTime createdAt;

  final int? httpStatus;
  final String? responseBody;
  final String? error;
  final DateTime? nextRetryAt;
  final DateTime? deliveredAt;
  final DateTime? failedAt;
}
