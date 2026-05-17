import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../application/broadcasts_providers.dart';
import '../../domain/broadcast.dart';
import '../widgets/broadcast_status_chip.dart';

/// `/admin/broadcasts` — lista de broadcasts (drafts + sent + failed).
class AdminBroadcastsPage extends ConsumerWidget {
  const AdminBroadcastsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(broadcastsListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.admin),
        ),
        title: Text(l.broadcastsTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(broadcastsListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.broadcastsNew),
        onPressed: () => context.goNamed(RouteNames.adminBroadcastsNew),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: async.when(
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
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (_, i) => _BroadcastRow(broadcast: entries[i]),
              );
            },
          ),
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

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.goNamed(
          RouteNames.adminBroadcastDetail,
          pathParameters: {'id': b.id},
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.subject,
                      style: context.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  BroadcastStatusChip(status: b.status),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
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
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: b.progressFraction,
                    minHeight: 4,
                  ),
                ),
              ],
            ],
          ),
        ),
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
        return l.broadcastsTargetStatus(b.targetValue['status']?.toString() ?? '?');
    }
  }
}
