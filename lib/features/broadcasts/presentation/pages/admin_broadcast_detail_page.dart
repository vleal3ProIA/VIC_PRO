import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../application/broadcasts_providers.dart';
import '../../domain/broadcast.dart';
import '../widgets/broadcast_status_chip.dart';

/// `/admin/broadcasts/<id>` — detalle de un broadcast con stats.
/// Si está `sending`, hace polling cada 3s para actualizar el progreso
/// en vivo.
class AdminBroadcastDetailPage extends ConsumerStatefulWidget {
  const AdminBroadcastDetailPage({required this.broadcastId, super.key});
  final String broadcastId;

  @override
  ConsumerState<AdminBroadcastDetailPage> createState() =>
      _AdminBroadcastDetailPageState();
}

class _AdminBroadcastDetailPageState
    extends ConsumerState<AdminBroadcastDetailPage> {
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _ensurePolling(Broadcast b) {
    // Si está en sending y no hay timer activo, arrancar polling.
    if (b.isInFlight && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        ref.invalidate(broadcastDetailProvider(widget.broadcastId));
      });
    }
    // Si dejó de estar en sending, parar.
    if (!b.isInFlight && _pollTimer != null) {
      _pollTimer?.cancel();
      _pollTimer = null;
      // Invalidar la lista también — el status habrá cambiado.
      ref.invalidate(broadcastsListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(broadcastDetailProvider(widget.broadcastId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.adminBroadcasts),
        ),
        title: Text(l.broadcastsDetailTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(broadcastDetailProvider(widget.broadcastId)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: async.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.broadcastsLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(
                broadcastDetailProvider(widget.broadcastId),
              ),
              retryLabel: l.actionRetry,
            ),
            data: (b) {
              _ensurePolling(b);
              return _Body(broadcast: b);
            },
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.broadcast});
  final Broadcast broadcast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();
    final b = broadcast;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        b.subject,
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    BroadcastStatusChip(status: b.status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l.broadcastsCreatedAt(fmt.format(b.createdAt.toLocal())),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                if (b.finishedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l.broadcastsFinishedAt(
                      fmt.format(b.finishedAt!.toLocal()),
                    ),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Progress card.
        if (b.recipientsTotal > 0) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.broadcastsProgressLabel,
                    style: context.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: b.progressFraction,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _stat(
                          context,
                          l.broadcastsStatTotal,
                          b.recipientsTotal.toString(),
                        ),
                      ),
                      Expanded(
                        child: _stat(
                          context,
                          l.broadcastsStatSent,
                          b.sentCount.toString(),
                          color: context.colors.primary,
                        ),
                      ),
                      Expanded(
                        child: _stat(
                          context,
                          l.broadcastsStatFailed,
                          b.failedCount.toString(),
                          color: b.failedCount > 0
                              ? context.colors.error
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // Body preview (truncado en card scrollable).
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.broadcastsBodyPreview,
                  style: context.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    b.bodyHtml,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (b.lastError != null) ...[
          const SizedBox(height: 16),
          Card(
            color: context.colors.errorContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: context.colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      b.lastError!,
                      style: TextStyle(color: context.colors.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        // Delete (solo si no está en sending).
        if (!b.isInFlight)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: Icon(Icons.delete_outline, color: context.colors.error),
              label: Text(
                l.broadcastsDelete,
                style: TextStyle(color: context.colors.error),
              ),
              onPressed: () => _onDelete(context, ref),
            ),
          ),
      ],
    );
  }

  Future<void> _onDelete(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.broadcastsDeleteConfirmTitle,
      body: l.broadcastsDeleteConfirmBody,
      confirmLabel: l.broadcastsDelete,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true) return;
    try {
      await ref
          .read(broadcastsDataSourceProvider)
          .delete(broadcast.id);
      if (!context.mounted) return;
      ref.invalidate(broadcastsListProvider);
      context.goNamed(RouteNames.adminBroadcasts);
    } catch (_) {
      if (!context.mounted) return;
      context.showSnack(l.broadcastsDeleteError, isError: true);
    }
  }

  Widget _stat(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
