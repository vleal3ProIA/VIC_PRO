import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

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
/// Hace polling cada 60s — barato (RPC con index parcial) y suficiente
/// para una UX correcta sin meter Realtime de Supabase aún.
///
/// Cuando llegue 3.A.2 (realtime), este provider escuchará al canal
/// `notifications:user_id=eq.X` y se invalidará en cada INSERT.
final unreadNotificationsCountProvider = StreamProvider<int>((ref) async* {
  final ds = ref.watch(notificationsDataSourceProvider);
  // Primer fetch inmediato.
  yield await ds.unreadCount();
  // Polling cada 60s — paramos cuando el provider se dispose (ref.onDispose
  // limpia el Timer.periodic implícito al cancelar el subscription del
  // StreamProvider).
  await for (final _ in Stream<void>.periodic(const Duration(seconds: 60))) {
    yield await ds.unreadCount();
  }
});
