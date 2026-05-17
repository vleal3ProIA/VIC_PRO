import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';

import '../../application/notifications_providers.dart';

/// Icono de campana del AppBar con badge rojo mostrando el conteo de
/// notificaciones sin leer. Al pulsar, navega a `/notifications`.
///
/// El badge:
/// - Se oculta cuando count == 0.
/// - Muestra "9+" cuando count >= 10 (mantiene el badge compacto).
/// - Se actualiza vía `unreadNotificationsCountProvider` que hace
///   polling cada 60s.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final count = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;

    return Tooltip(
      message: count == 0
          ? l.notificationsBellTooltipEmpty
          : l.notificationsBellTooltipCount(count),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            // El IconButton lleva su propio tooltip vacío para que el
            // Tooltip exterior gane (puede mostrar count dinámico).
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.goNamed(RouteNames.notifications),
          ),
          if (count > 0)
            Positioned(
              right: 6,
              top: 6,
              child: IgnorePointer(
                // Que el badge no robe taps al IconButton.
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: context.colors.error,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: context.colors.surface,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    count >= 10 ? '9+' : '$count',
                    style: TextStyle(
                      color: context.colors.onError,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
