import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/webhooks_providers.dart';
import '../../domain/webhook_delivery.dart';
import '../../domain/webhook_endpoint.dart';

/// `/account-settings/webhooks/<id>` — detalle de un endpoint con su
/// configuración + histórico de los últimos 50 deliveries (success /
/// retry / failed) con HTTP status, intentos y error.
class WebhookDetailPage extends ConsumerWidget {
  const WebhookDetailPage({required this.endpointId, super.key});

  final String endpointId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final endpointsAsync = ref.watch(webhookEndpointsProvider);
    final deliveriesAsync = ref.watch(
      webhookDeliveriesProvider(endpointId),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.webhooks),
        ),
        title: Text(l.webhooksDetailTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref
                ..invalidate(webhookEndpointsProvider)
                ..invalidate(webhookDeliveriesProvider(endpointId));
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: endpointsAsync.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.webhooksLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(webhookEndpointsProvider),
              retryLabel: l.actionRetry,
            ),
            data: (list) {
              WebhookEndpoint? endpoint;
              for (final e in list) {
                if (e.id == endpointId) {
                  endpoint = e;
                  break;
                }
              }
              if (endpoint == null) {
                return AppEmptyState(
                  icon: Icons.error_outline,
                  title: l.webhooksDetailNotFoundTitle,
                  message: l.webhooksDetailNotFoundBody,
                );
              }
              return _DetailBody(
                endpoint: endpoint,
                deliveriesAsync: deliveriesAsync,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.endpoint,
    required this.deliveriesAsync,
  });

  final WebhookEndpoint endpoint;
  final AsyncValue<List<WebhookDelivery>> deliveriesAsync;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.link, color: context.colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        endpoint.url,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
                if (endpoint.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(
                    endpoint.description!,
                    style: context.textTheme.bodyMedium,
                  ),
                ],
                const Divider(height: 24),
                _MetaRow(
                  icon: Icons.label_outline,
                  label: l.webhooksFieldEvents,
                  value: endpoint.isWildcard
                      ? l.webhooksEventAll
                      : endpoint.events.join(', '),
                ),
                _MetaRow(
                  icon: Icons.warning_amber_outlined,
                  label: l.webhooksConsecutiveFailures,
                  value: endpoint.consecutiveFailures.toString(),
                ),
                if (endpoint.autoDisabled)
                  _MetaRow(
                    icon: Icons.block,
                    label: l.webhooksDisabledReason,
                    value: l.webhooksStatusAutoDisabled,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l.webhooksRecentDeliveries,
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        deliveriesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l.webhooksDeliveriesLoadError,
              style: TextStyle(color: context.colors.error),
            ),
          ),
          data: (deliveries) {
            if (deliveries.isEmpty) {
              return AppEmptyState(
                icon: Icons.history,
                title: l.webhooksDeliveriesEmptyTitle,
                message: l.webhooksDeliveriesEmptyBody,
              );
            }
            return Column(
              children: [
                for (final d in deliveries) _DeliveryTile(delivery: d),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: context.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _DeliveryTile extends StatelessWidget {
  const _DeliveryTile({required this.delivery});
  final WebhookDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hms();
    final (icon, color) = _statusVisual(context, delivery.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(
          delivery.eventType,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        subtitle: Text(
          '${_statusLabel(l, delivery.status)} • '
          '${l.webhooksAttempt(delivery.attempt)} • '
          '${fmt.format(delivery.createdAt.toLocal())}',
          style: context.textTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (delivery.httpStatus != null)
                  _kv(
                    context,
                    'HTTP',
                    delivery.httpStatus.toString(),
                  ),
                if (delivery.error != null)
                  _kv(
                    context,
                    l.webhooksError,
                    delivery.error!,
                    color: context.colors.error,
                  ),
                if (delivery.responseBody?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(
                    l.webhooksResponseBody,
                    style: context.textTheme.labelSmall,
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      delivery.responseBody!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                if (delivery.nextRetryAt != null)
                  _kv(
                    context,
                    l.webhooksNextRetry,
                    fmt.format(delivery.nextRetryAt!.toLocal()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(
    BuildContext context,
    String k,
    String v, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: context.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _statusVisual(
    BuildContext context,
    WebhookDeliveryStatus status,
  ) {
    switch (status) {
      case WebhookDeliveryStatus.success:
        return (Icons.check_circle, context.colors.primary);
      case WebhookDeliveryStatus.retry:
        return (Icons.schedule, Colors.amber.shade800);
      case WebhookDeliveryStatus.failed:
        return (Icons.error, context.colors.error);
      case WebhookDeliveryStatus.pending:
        return (Icons.hourglass_empty, context.colors.onSurfaceVariant);
    }
  }

  String _statusLabel(AppLocalizations l, WebhookDeliveryStatus s) {
    switch (s) {
      case WebhookDeliveryStatus.success:
        return l.webhooksDeliverySuccess;
      case WebhookDeliveryStatus.retry:
        return l.webhooksDeliveryRetry;
      case WebhookDeliveryStatus.failed:
        return l.webhooksDeliveryFailed;
      case WebhookDeliveryStatus.pending:
        return l.webhooksDeliveryPending;
    }
  }
}
