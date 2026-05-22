import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_pagination_bar.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/broadcasts_providers.dart';
import '../../domain/broadcast.dart';
import '../widgets/broadcast_status_chip.dart';

/// `/admin/broadcasts` — lista de broadcasts (drafts + sent + failed).
class AdminBroadcastsPage extends ConsumerWidget {
  const AdminBroadcastsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.admin),
        ),
        title: Text(l.broadcastsTitle),
      ),
      body: const AdminBroadcastsView(),
    );
  }
}

/// Cuerpo de la lista de broadcasts (sin Scaffold). Reutilizable como página
/// completa o embebido en el master-detail de Administración.
///
/// El botón "Nuevo" (antes un FAB) se reposiciona dentro del panel; navega a
/// la página de composición a pantalla completa.
class AdminBroadcastsView extends ConsumerStatefulWidget {
  const AdminBroadcastsView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Admin).
  final bool embedded;

  @override
  ConsumerState<AdminBroadcastsView> createState() =>
      _AdminBroadcastsViewState();
}

class _AdminBroadcastsViewState extends ConsumerState<AdminBroadcastsView> {
  int _page = 0;
  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(broadcastsListProvider);

    final content = async.when(
      loading: () => const AppLoadingState(),
      error: (e, _) => AppErrorState(
        message: l.broadcastsLoadError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(broadcastsListProvider),
        retryLabel: l.actionRetry,
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return AppEmptyState(
            icon: Icons.campaign_outlined,
            title: l.broadcastsEmptyTitle,
            message: l.broadcastsEmptyBody,
          );
        }
        final totalPages = (entries.length / _pageSize).ceil();
        final page = _page.clamp(0, totalPages - 1);
        final start = page * _pageSize;
        final end = (start + _pageSize) > entries.length
            ? entries.length
            : start + _pageSize;
        final pageEntries = entries.sublist(start, end);
        final list = ListView.separated(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            widget.embedded ? AppSpacing.md : 96,
          ),
          shrinkWrap: widget.embedded,
          physics:
              widget.embedded ? const NeverScrollableScrollPhysics() : null,
          itemCount: pageEntries.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) => _BroadcastRow(broadcast: pageEntries[i]),
        );
        return Column(
          mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (widget.embedded) list else Expanded(child: list),
            AppPaginationBar(
              currentPage: page,
              totalPages: totalPages,
              onPrevious: () => setState(() => _page = page - 1),
              onNext: () => setState(() => _page = page + 1),
            ),
          ],
        );
      },
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
        child: Column(
          mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // Acciones del panel (antes refresh en AppBar + FAB "Nuevo").
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: l.actionRetry,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.invalidate(broadcastsListProvider),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: () =>
                        context.pushNamed(RouteNames.adminBroadcastsNew),
                    icon: const Icon(Icons.add),
                    label: Text(l.broadcastsNew),
                  ),
                ],
              ),
            ),
            if (widget.embedded) content else Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _BroadcastRow extends ConsumerWidget {
  const _BroadcastRow({required this.broadcast});
  final Broadcast broadcast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();
    final b = broadcast;

    return PremiumCard(
      onTap: () => context.pushNamed(
        RouteNames.adminBroadcastDetail,
        pathParameters: {'id': b.id},
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  b.subject,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              BroadcastStatusChip(status: b.status),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 2,
            children: [
              Text(
                _targetLabel(context, b),
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              if (b.status != BroadcastStatus.draft)
                Text(
                  l.broadcastsProgress(
                    b.sentCount,
                    b.recipientsTotal,
                  ),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (b.failedCount > 0)
                Text(
                  l.broadcastsFailed(b.failedCount),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              Text(
                fmt.format(b.createdAt.toLocal()),
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (b.isInFlight) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadii.brSm,
              child: LinearProgressIndicator(
                value: b.progressFraction,
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _targetLabel(BuildContext context, Broadcast b) {
    final l = context.l10n;
    switch (b.targetType) {
      case BroadcastTargetType.all:
        return l.broadcastsTargetAll;
      case BroadcastTargetType.plan:
        return l.broadcastsTargetPlan(b.targetValue['slug']?.toString() ?? '?');
      case BroadcastTargetType.language:
        return l.broadcastsTargetLanguage(
          (b.targetValue['code']?.toString() ?? '?').toUpperCase(),
        );
      case BroadcastTargetType.status:
        return l
            .broadcastsTargetStatus(b.targetValue['status']?.toString() ?? '?');
    }
  }
}
