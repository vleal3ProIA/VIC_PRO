import 'package:meta/meta.dart';

/// Nivel visual / severidad de una notificación. Mapea a `notification_type`
/// en Postgres y determina el icono + color en la UI.
enum AppNotificationType {
  info,
  success,
  warning,
  error;

  static AppNotificationType fromString(String raw) {
    switch (raw) {
      case 'success':
        return AppNotificationType.success;
      case 'warning':
        return AppNotificationType.warning;
      case 'error':
        return AppNotificationType.error;
      case 'info':
      default:
        return AppNotificationType.info;
    }
  }
}

/// Notificación in-app dirigida a UN usuario. Se hidrata desde una fila
/// de `public.notifications`.
///
/// El nombre `AppNotification` (no `Notification`) evita colisionar con
/// `Notification` de Flutter (`flutter/widgets.dart` lo define).
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.tenantId,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    required this.actionUrl,
    required this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    DateTime? parseTs(Object? v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return AppNotification(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      tenantId: m['tenant_id'] as String?,
      type: AppNotificationType.fromString(m['type'] as String),
      category: m['category'] as String,
      title: m['title'] as String,
      body: m['body'] as String?,
      actionUrl: m['action_url'] as String?,
      readAt: parseTs(m['read_at']),
      createdAt: parseTs(m['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String userId;
  final String? tenantId;
  final AppNotificationType type;

  /// Agrupador libre (`billing`, `team`, `system`, `security`…). Útil
  /// cuando la pantalla `/notifications` añada filtros por categoría y
  /// para que el user configure preferencias por canal/categoría.
  final String category;

  final String title;
  final String? body;

  /// Deep link interno (p.ej. `/billing/invoices`). Si no es null, la
  /// card de la notif es tappable y navega allí.
  final String? actionUrl;

  /// `null` = sin leer. Tras `markAsRead`, queda a `now()`.
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;
  bool get isUnread => readAt == null;
}
