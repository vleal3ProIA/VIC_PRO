import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../application/notifications_providers.dart';
import '../../domain/app_notification.dart';

/// `/notifications` — historial de notificaciones in-app del usuario.
///
/// Las notif sin leer se destacan visualmente (background tinted +
/// fontWeight bold). Click en una notif: marca como leída + si tiene
/// `actionUrl`, navega allí.
///
/// AppBar action "Marcar todas como leídas" cuando hay alguna sin
/// leer.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(notificationsListProvider);
    final unreadCount =
        ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.accountSettings),
        ),
        title: Text(l.notificationsTitle),
        actions: [
          if (unreadCount > 0)
            TextButton.icon(
              icon: const Icon(Icons.done_all, size: 18),
              label: Text(l.notificationsMarkAllRead),
              onPressed: () => _onMarkAllRead(context, ref),
            ),
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref
                ..invalidate(notificationsListProvider)
                ..invalidate(unreadNotificationsCountProvider);
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: async.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.notificationsLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(notificationsListProvider),
              retryLabel: l.actionRetry,
            ),
            data: (items) {
              if (items.isEmpty) {
                return AppEmptyState(
                  icon: Icons.notifications_none_outlined,
                  title: l.notificationsEmptyTitle,
                  message: l.notificationsEmptyBody,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _NotificationCard(item: items[i]),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onMarkAllRead(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    try {
      final n = await ref
          .read(notificationsDataSourceProvider)
          .markAllAsRead();
      if (!context.mounted) return;
      ref
        ..invalidate(notificationsListProvider)
        ..invalidate(unreadNotificationsCountProvider);
      context.showSnack(l.notificationsMarkedAllRead(n));
    } catch (_) {
      if (!context.mounted) return;
      context.showSnack(l.notificationsActionError, isError: true);
    }
  }
}

class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({required this.item});
  final AppNotification item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();
    final (icon, color) = _iconAndColor(context, item.type);

    return Card(
      color: item.isUnread
          ? context.colors.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _onTap(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: context.textTheme.titleSmall?.copyWith(
                              fontWeight: item.isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (item.isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: context.colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (item.body != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.body!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      fmt.format(item.createdAt.toLocal()),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    // 1) Marcar como leída (silent fail si no había nada que marcar).
    if (item.isUnread) {
      try {
        await ref
            .read(notificationsDataSourceProvider)
            .markAsRead(item.id);
        ref
          ..invalidate(notificationsListProvider)
          ..invalidate(unreadNotificationsCountProvider);
      } catch (_) {
        // No bloqueamos la navegación por un fallo de mark.
      }
    }
    // 2) Si la notif tiene deep link, navegar allí.
    if (!context.mounted) return;
    final url = item.actionUrl;
    if (url != null && url.isNotEmpty && url.startsWith('/')) {
      // Solo aceptamos rutas internas — un actionUrl externo se ignora
      // por seguridad (un cliente malicioso podría intentar abrir
      // sitios externos via notifs).
      context.go(url);
    }
  }

  (IconData, Color) _iconAndColor(BuildContext context, AppNotificationType t) {
    switch (t) {
      case AppNotificationType.success:
        return (Icons.check_circle_outline, context.colors.primary);
      case AppNotificationType.warning:
        return (Icons.warning_amber_outlined, context.colors.tertiary);
      case AppNotificationType.error:
        return (Icons.error_outline, context.colors.error);
      case AppNotificationType.info:
        return (Icons.info_outline, context.colors.secondary);
    }
  }
}
