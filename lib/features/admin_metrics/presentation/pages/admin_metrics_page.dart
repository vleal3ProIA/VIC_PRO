import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/admin_metrics_providers.dart';
import '../../domain/admin_metrics.dart';
import '../widgets/funnel_view.dart';
import '../widgets/metric_line_chart.dart';
import '../widgets/plan_distribution_bars.dart';

/// `/admin/metrics` — dashboard de métricas. Overview cards + 2
/// gráficos temporales (signups, MRR) + distribución por plan +
/// conversion funnel. Selector de rango temporal arriba.
class AdminMetricsPage extends ConsumerWidget {
  const AdminMetricsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final overview = ref.watch(adminMetricsOverviewProvider);
    final range = ref.watch(adminMetricsRangeProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.admin),
        ),
        title: Text(l.adminMetricsTitle),
        actions: [
          // Selector de rango temporal — afecta a signups/mrr.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButton<MetricsRange>(
              value: range,
              underline: const SizedBox.shrink(),
              onChanged: (r) {
                if (r == null) return;
                ref.read(adminMetricsRangeProvider.notifier).state = r;
              },
              items: [
                for (final r in MetricsRange.values)
                  DropdownMenuItem(
                    value: r,
                    child: Text(_rangeLabel(context, r)),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref
                ..invalidate(adminMetricsOverviewProvider)
                ..invalidate(adminMetricsSignupsProvider)
                ..invalidate(adminMetricsMrrProvider)
                ..invalidate(adminMetricsPlanDistributionProvider)
                ..invalidate(adminMetricsFunnelProvider);
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: overview.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.adminMetricsLoadError,
              detail: e.toString(),
              onRetry: () =>
                  ref.invalidate(adminMetricsOverviewProvider),
              retryLabel: l.actionRetry,
            ),
            data: (ov) => _Body(overview: ov, range: range),
          ),
        ),
      ),
    );
  }

  String _rangeLabel(BuildContext context, MetricsRange r) {
    final l = context.l10n;
    return switch (r) {
      MetricsRange.d7 => l.adminMetricsRange7d,
      MetricsRange.d30 => l.adminMetricsRange30d,
      MetricsRange.d90 => l.adminMetricsRange90d,
      MetricsRange.d365 => l.adminMetricsRange365d,
    };
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.overview, required this.range});
  final MetricsOverview overview;
  final MetricsRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final signupsAsync = ref.watch(adminMetricsSignupsProvider);
    final mrrAsync = ref.watch(adminMetricsMrrProvider);
    final plansAsync = ref.watch(adminMetricsPlanDistributionProvider);
    final funnelAsync = ref.watch(adminMetricsFunnelProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ─── Overview cards ───
        _OverviewCards(overview: overview),
        const SizedBox(height: 20),
        // ─── Signups chart ───
        _ChartCard(
          title: l.adminMetricsSignupsTitle,
          subtitle: l.adminMetricsSignupsSubtitle(range.days),
          child: signupsAsync.when(
            loading: () =>
                const SizedBox(height: 220, child: AppLoadingState()),
            error: (_, __) => _chartError(context, l),
            data: (points) => SizedBox(
              height: 220,
              child: MetricLineChart(
                points: points,
                formatValue: (v) => v.toInt().toString(),
                semanticsLabel: l.adminMetricsSignupsTitle,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ─── MRR chart ───
        _ChartCard(
          title: l.adminMetricsMrrTitle,
          subtitle: l.adminMetricsMrrSubtitle(range.days),
          child: mrrAsync.when(
            loading: () =>
                const SizedBox(height: 220, child: AppLoadingState()),
            error: (_, __) => _chartError(context, l),
            data: (points) => SizedBox(
              height: 220,
              child: MetricLineChart(
                points: points,
                color: Theme.of(context).colorScheme.tertiary,
                formatValue: (v) {
                  // cents -> euros
                  final eur = v / 100;
                  if (eur >= 1000) {
                    return '${(eur / 1000).toStringAsFixed(1)}k€';
                  }
                  return '${eur.toStringAsFixed(0)}€';
                },
                semanticsLabel: l.adminMetricsMrrTitle,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ─── Plan distribution + Funnel side by side ───
        LayoutBuilder(
          builder: (context, c) {
            final isWide = c.maxWidth > 800;
            final cards = [
              Expanded(
                child: _ChartCard(
                  title: l.adminMetricsPlanDistTitle,
                  subtitle: l.adminMetricsPlanDistSubtitle,
                  child: plansAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => _chartError(context, l),
                    data: (rows) => PlanDistributionBars(rows: rows),
                  ),
                ),
              ),
              const SizedBox(width: 16, height: 16),
              Expanded(
                child: _ChartCard(
                  title: l.adminMetricsFunnelTitle,
                  subtitle: l.adminMetricsFunnelSubtitle,
                  child: funnelAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => _chartError(context, l),
                    data: (f) => FunnelView(funnel: f),
                  ),
                ),
              ),
            ];
            return isWide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: cards)
                : Column(children: cards);
          },
        ),
      ],
    );
  }

  Widget _chartError(BuildContext context, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: context.colors.error, size: 16),
          const SizedBox(width: 6),
          Text(
            l.adminMetricsChartError,
            style: TextStyle(color: context.colors.error),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── Overview cards ───────────────────────

class _OverviewCards extends StatelessWidget {
  const _OverviewCards({required this.overview});
  final MetricsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _OverviewCard(
          icon: Icons.people,
          label: l.adminMetricsKpiTotalUsers,
          value: overview.totalUsers.toString(),
          subtitle: l.adminMetricsKpiNew30d(overview.newUsers30d),
        ),
        _OverviewCard(
          icon: Icons.workspace_premium,
          label: l.adminMetricsKpiPayingTenants,
          value: overview.payingTenants.toString(),
          subtitle: '${overview.conversionPct.toStringAsFixed(1)}%',
          color: context.colors.tertiary,
        ),
        _OverviewCard(
          icon: Icons.trending_up,
          label: l.adminMetricsKpiMrr,
          value: _formatMoneyCents(overview.mrrCents),
          subtitle: l.adminMetricsKpiArr(_formatMoneyCents(overview.arrCents)),
          color: context.colors.primary,
        ),
        _OverviewCard(
          icon: Icons.shopping_bag_outlined,
          label: l.adminMetricsKpiActiveSubs,
          value: overview.activeSubs.toString(),
          subtitle: l.adminMetricsKpiChurned30d(overview.churned30d),
        ),
      ],
    );
  }

  String _formatMoneyCents(int cents) {
    final eur = cents / 100;
    if (eur >= 1000) return '${(eur / 1000).toStringAsFixed(1)}k €';
    return '${eur.toStringAsFixed(2)} €';
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.onSurface;
    return SizedBox(
      width: 230,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: c),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: context.textTheme.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      value,
                      style: context.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
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
}

// ─────────────────────── Chart card wrapper ───────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              subtitle,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
