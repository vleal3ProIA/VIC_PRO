import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_notification.dart';

/// Acceso de lectura + acciones (mark-as-read) sobre `public.notifications`.
/// La INSERCIÓN solo la hace service_role desde Edge Functions — el
/// cliente nunca crea notificaciones para sí mismo.
class NotificationsDataSource {
  const NotificationsDataSource(this._client);

  final SupabaseClient _client;

  /// Lista las notificaciones del usuario actual ordenadas desc por
  /// fecha. RLS limita a las suyas.
  Future<List<AppNotification>> list({int limit = 100}) async {
    final data = await _client
        .from('notifications')
        .select(
          'id, user_id, tenant_id, type, category, title, body, '
          'action_url, read_at, created_at',
        )
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(AppNotification.fromMap)
        .toList(growable: false);
  }

  /// Conteo de no leídas — usado por el badge de la campana. La RPC
  /// `get_unread_notifications_count` usa un index parcial: barato
  /// incluso con miles de notificaciones leídas en el histórico.
  Future<int> unreadCount() async {
    final result = await _client.rpc<dynamic>('get_unread_notifications_count');
    if (result is int) return result;
    if (result is num) return result.toInt();
    return 0;
  }

  /// Marca UNA notificación como leída. Devuelve true si la marcó
  /// (false si ya estaba leída o no era del usuario).
  Future<bool> markAsRead(String id) async {
    final result = await _client.rpc<dynamic>(
      'mark_notification_read',
      params: {'p_id': id},
    );
    return result == true;
  }

  /// Marca TODAS las no leídas como leídas. Devuelve cuántas afectó.
  Future<int> markAllAsRead() async {
    final result = await _client.rpc<dynamic>('mark_all_notifications_read');
    if (result is int) return result;
    if (result is num) return result.toInt();
    return 0;
  }

  /// Borra una notificación. RLS la limita a las propias.
  Future<void> delete(String id) async {
    await _client.from('notifications').delete().eq('id', id);
  }
}
