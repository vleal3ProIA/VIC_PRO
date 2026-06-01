import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/notifications_datasource.dart';
import '../domain/app_notification.dart';

final notificationsDataSourceProvider =
    Provider<NotificationsDataSource>((ref) {
  return NotificationsDataSource(ref.watch(supabaseClientProvider));
});

/// Lista completa para la pantalla `/notifications`. Se invalida tras
/// `markAsRead`, `markAllAsRead` o `delete`.
final notificationsListProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  final ds = ref.watch(notificationsDataSourceProvider);
  return ds.list();
});

/// Conteo de no leídas para el badge de la campana en el AppBar.
///
/// Realtime: se suscribe al canal Postgres-changes de `notifications`
/// filtrado por `user_id = <uid actual>` y refresca el contador en:
///   - INSERT  → nueva notif → +1.
///   - UPDATE  → tipicamente cuando read_at pasa a no-null → -1.
///   - DELETE  → notif borrada → recalcular.
///
/// Fallback: polling cada 60s para protegerse de pérdidas de conexion
/// websocket (mobile bg, sleep, etc.). Cuando el realtime funciona, el
/// polling es redundante pero barato (RPC con index parcial).
final unreadNotificationsCountProvider = StreamProvider<int>((ref) async* {
  final ds = ref.watch(notificationsDataSourceProvider);
  final client = ref.watch(supabaseClientProvider);
  final uid = client.auth.currentUser?.id;

  // Primer fetch inmediato.
  yield await ds.unreadCount();

  // Si no hay sesión, no montamos canal — el provider quedará en este
  // valor hasta que el AuthState cambie y el provider se reconstruya
  // (el listener de auth state en otros providers se encarga).
  if (uid == null) {
    return;
  }

  // ── Canal Realtime ──
  // Un solo canal con dos listeners (INSERT y UPDATE). Eventos llegan
  // via StreamController para mezclarlos con el polling.
  final controller = StreamController<int>();
  final channel = client.channel('public:notifications:user:$uid');
  channel.onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'notifications',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: uid,
    ),
    callback: (_) async {
      try {
        controller.add(await ds.unreadCount());
      } catch (_) {/* swallow — el polling rescatará */}
    },
  );
  channel.onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'notifications',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: uid,
    ),
    callback: (_) async {
      try {
        controller.add(await ds.unreadCount());
      } catch (_) {/* swallow */}
    },
  );
  channel.onPostgresChanges(
    event: PostgresChangeEvent.delete,
    schema: 'public',
    table: 'notifications',
    callback: (_) async {
      // DELETE no soporta filtro de user_id (RLS filtra payload pero el
      // listener recibe el evento igual). Refrescamos siempre.
      try {
        controller.add(await ds.unreadCount());
      } catch (_) {/* swallow */}
    },
  );
  channel.subscribe();

  // Polling de respaldo cada 60s.
  final pollTimer = Timer.periodic(
    const Duration(seconds: 60),
    (_) async {
      try {
        controller.add(await ds.unreadCount());
      } catch (_) {/* swallow */}
    },
  );

  // Cleanup al dispose del provider.
  ref.onDispose(() {
    pollTimer.cancel();
    client.removeChannel(channel);
    controller.close();
  });

  // Emite todo lo que entre por el controller (realtime + polling).
  yield* controller.stream;
});
