import 'package:meta/meta.dart';

/// Endpoint webhook configurado por el user para recibir eventos
/// salientes (POST) cuando algo pasa en la app.
@immutable
class WebhookEndpoint {
  const WebhookEndpoint({
    required this.id,
    required this.userId,
    required this.url,
    required this.events,
    required this.active,
    required this.consecutiveFailures,
    required this.createdAt,
    required this.updatedAt,
    this.tenantId,
    this.description,
    this.disabledReason,
    this.secret,
  });

  factory WebhookEndpoint.fromMap(Map<String, dynamic> m) {
    return WebhookEndpoint(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      tenantId: m['tenant_id'] as String?,
      url: m['url'] as String,
      description: m['description'] as String?,
      events: (m['events'] as List?)?.cast<String>() ?? const ['*'],
      active: m['active'] as bool? ?? true,
      consecutiveFailures:
          (m['consecutive_failures'] as num?)?.toInt() ?? 0,
      disabledReason: m['disabled_reason'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
      secret: m['secret'] as String?,
    );
  }

  final String id;
  final String userId;
  final String? tenantId;
  final String url;
  final String? description;

  /// Lista de eventos suscritos. `['*']` = todos.
  final List<String> events;

  final bool active;
  final int consecutiveFailures;

  /// Si `active = false`, indica por qué: `'manual'` o
  /// `'too_many_failures'` (auto-deshabilitado tras 10 fallos).
  final String? disabledReason;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Secret raw (`whsec_<base64url>`). SOLO presente justo tras crear.
  final String? secret;

  bool get isWildcard => events.contains('*');
  bool get autoDisabled => disabledReason == 'too_many_failures';

  /// `true` si el endpoint ha tenido al menos un fallo desde el
  /// último éxito (útil para mostrar warning amarillo).
  bool get hasRecentFailures => consecutiveFailures > 0;
}
