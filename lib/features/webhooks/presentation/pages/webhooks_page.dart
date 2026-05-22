import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_pagination_bar.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/webhooks_providers.dart';
import '../../domain/webhook_endpoint.dart';
import '../widgets/create_webhook_dialog.dart';
import '../widgets/webhook_secret_dialog.dart';

/// `/account-settings/webhooks` — gestiona los endpoints salientes
/// del usuario. Cada item tiene su detalle propio en
/// `/account-settings/webhooks/<id>` con histórico de deliveries.
class WebhooksPage extends ConsumerStatefulWidget {
  const WebhooksPage({super.key});

  @override
  ConsumerState<WebhooksPage> createState() => _WebhooksPageState();
}

class _WebhooksPageState extends ConsumerState<WebhooksPage> {
  int _page = 0;
  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(webhookEndpointsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.accountSettings),
        ),
        title: Text(l.webhooksTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(webhookEndpointsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.webhooksCreate),
        onPressed: _onCreate,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: double.infinity),
          child: async.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.webhooksLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(webhookEndpointsProvider),
              retryLabel: l.actionRetry,
            ),
            data: (endpoints) {
              if (endpoints.isEmpty) {
                return AppEmptyState(
                  icon: Icons.webhook_outlined,
                  title: l.webhooksEmptyTitle,
                  message: l.webhooksEmptyBody,
                );
              }
              final totalPages = (endpoints.length / _pageSize).ceil();
              final page = _page.clamp(0, totalPages - 1);
              final start = page * _pageSize;
              final end = (start + _pageSize) > endpoints.length
                  ? endpoints.length
                  : start + _pageSize;
              final pageEndpoints = endpoints.sublist(start, end);
              return Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      // +1 por el _IntroCard fijo en la posición 0.
                      itemCount: pageEndpoints.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        if (i == 0) return _IntroCard(l: l);
                        return _EndpointTile(endpoint: pageEndpoints[i - 1]);
                      },
                    ),
                  ),
                  AppPaginationBar(
                    currentPage: page,
                    totalPages: totalPages,
                    onPrevious: () => setState(() => _page = page - 1),
                    onNext: () => setState(() => _page = page + 1),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onCreate() async {
    final l = context.l10n;
    final result = await showDialog<WebhookEndpoint>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateWebhookDialog(),
    );
    if (result == null || !mounted) return;
    ref.invalidate(webhookEndpointsProvider);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WebhookSecretDialog(endpoint: result),
    );
    if (!mounted) return;
    context.showSnack(l.webhooksCreated);
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: context.colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: context.colors.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.webhooksIntro,
                style: context.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndpointTile extends ConsumerStatefulWidget {
  const _EndpointTile({required this.endpoint});
  final WebhookEndpoint endpoint;

  @override
  ConsumerState<_EndpointTile> createState() => _EndpointTileState();
}

class _EndpointTileState extends ConsumerState<_EndpointTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();
    final e = widget.endpoint;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.pushNamed(
          RouteNames.webhookDetail,
          pathParameters: {'id': e.id},
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                e.active
                    ? Icons.webhook_outlined
                    : Icons.pause_circle_outline,
                color: e.active
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (e.description?.isNotEmpty ?? false)
                                ? e.description!
                                : e.url,
                            style: context.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (e.autoDisabled)
                          _StatusChip(
                            label: l.webhooksStatusAutoDisabled,
                            color: context.colors.error,
                          )
                        else if (!e.active)
                          _StatusChip(
                            label: l.webhooksStatusPaused,
                            color: context.colors.onSurfaceVariant,
                          )
                        else if (e.hasRecentFailures)
                          _StatusChip(
                            label: l.webhooksStatusFailing(
                              e.consecutiveFailures,
                            ),
                            color: Colors.amber.shade800,
                          )
                        else
                          _StatusChip(
                            label: l.webhooksStatusActive,
                            color: context.colors.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (e.description?.isNotEmpty ?? false)
                      Text(
                        e.url,
                        style: context.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: context.colors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (e.isWildcard)
                          _EventChip(label: l.webhooksEventAll)
                        else
                          for (final ev in e.events) _EventChip(label: ev),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.webhooksCreatedAt(fmt.format(e.createdAt.toLocal())),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_busy,
                tooltip: l.webhooksActions,
                onSelected: (v) async {
                  switch (v) {
                    case 'test':
                      await _onTest();
                    case 'pause':
                      await _setActive(false);
                    case 'resume':
                      await _setActive(true);
                    case 'delete':
                      await _onDelete();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'test',
                    child: Row(
                      children: [
                        const Icon(Icons.send_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(l.webhooksSendTest),
                      ],
                    ),
                  ),
                  if (e.active)
                    PopupMenuItem(
                      value: 'pause',
                      child: Row(
                        children: [
                          const Icon(Icons.pause_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(l.webhooksPause),
                        ],
                      ),
                    )
                  else
                    PopupMenuItem(
                      value: 'resume',
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(l.webhooksResume),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: context.colors.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l.webhooksDelete,
                          style: TextStyle(color: context.colors.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onTest() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(webhooksDataSourceProvider)
          .sendTestPing(widget.endpoint.id);
      if (!mounted) return;
      ref
        ..invalidate(webhookEndpointsProvider)
        ..invalidate(webhookDeliveriesProvider(widget.endpoint.id));
      context.showSnack(
        result.success
            ? l.webhooksTestSuccess(result.httpStatus ?? 200)
            : l.webhooksTestFailed(
                result.httpStatus?.toString() ?? result.error ?? '?',
              ),
        isError: !result.success,
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.webhooksTestError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setActive(bool active) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref
          .read(webhooksDataSourceProvider)
          .setActive(widget.endpoint.id, active: active);
      if (!mounted) return;
      ref.invalidate(webhookEndpointsProvider);
      context.showSnack(active ? l.webhooksResumed : l.webhooksPaused);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.webhooksStateError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onDelete() async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.webhooksDeleteConfirmTitle,
      body: l.webhooksDeleteConfirmBody(
        (widget.endpoint.description?.isNotEmpty ?? false)
            ? widget.endpoint.description!
            : widget.endpoint.url,
      ),
      confirmLabel: l.webhooksDelete,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(webhooksDataSourceProvider)
          .delete(widget.endpoint.id);
      if (!mounted) return;
      ref.invalidate(webhookEndpointsProvider);
      context.showSnack(l.webhooksDeleted);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.webhooksDeleteError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EventChip extends StatelessWidget {
  const _EventChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          fontFamily: 'monospace',
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
