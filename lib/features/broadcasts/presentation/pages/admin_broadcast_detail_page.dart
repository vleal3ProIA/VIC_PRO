import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/broadcasts_providers.dart';
import '../../domain/broadcast.dart';
import '../widgets/broadcast_status_chip.dart';

/// `/admin/broadcasts/<id>` — detalle de un broadcast con stats.
///
/// **Rediseno Premium UI Fase 10**: Cards Material -> PremiumCards,
/// SectionHeader para sub-bloques, PremiumButton destructive para
/// delete. Mantiene polling cada 3s si esta `sending` (igual que el
/// codigo anterior) y todos los callbacks (onDelete con confirm
/// dialog, invalidacion del provider de lista).
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
          constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // ─── Header card ───
        PremiumCard(
          padding: const EdgeInsets.all(AppSpacing.md),
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
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  BroadcastStatusChip(status: b.status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
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
        const SizedBox(height: AppSpacing.md),
        // ─── Progress card ───
        if (b.recipientsTotal > 0) ...[
          PremiumCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: l.broadcastsProgressLabel,
                  compact: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: AppRadii.brSm,
                  child: LinearProgressIndicator(
                    value: b.progressFraction,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
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
          const SizedBox(height: AppSpacing.md),
        ],
        // ─── Body preview card ───
        PremiumCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: l.broadcastsBodyPreview,
                compact: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 4),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: AppRadii.brSm,
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
        if (b.lastError != null) ...[
          const SizedBox(height: AppSpacing.md),
          PremiumCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: context.colors.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SelectableText(
                    b.lastError!,
                    style: TextStyle(color: context.colors.error),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        // ─── Delete (solo si no está en sending) ───
        if (!b.isInFlight)
          Align(
            alignment: Alignment.centerRight,
            child: PremiumButton(
              label: l.broadcastsDelete,
              variant: PremiumButtonVariant.destructive,
              size: PremiumButtonSize.sm,
              leadingIcon: Icons.delete_outline,
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
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: color,
          ),
        ),
      ],
    );
  }
}
