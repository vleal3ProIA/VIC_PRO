import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/admin_metrics_providers.dart';
import '../../domain/admin_metrics.dart';
import '../widgets/funnel_view.dart';
import '../widgets/metric_line_chart.dart';
import '../widgets/plan_distribution_bars.dart';

/// `/admin/metrics` — dashboard de metricas (Premium UI Fase 8).
///
/// **Antes**: AppBar + `_OverviewCard`s custom (Material Card) +
/// `_ChartCard`s con titulo en bold + selector de rango en AppBar
/// actions.
///
/// **Despues**: AppBar minimal solo con back + selector de rango;
/// `PageHeader` con titulo + subtitle + actions (refresh); 4 KPIs
/// con `KpiCard` premium (icono coloreado + valor grande); 4 charts
/// en `PremiumCard` con `SectionHeader` interno.
///
/// **Logica preservada al 100%**: providers, widgets de charts
/// (MetricLineChart, PlanDistributionBars, FunnelView), rango temporal,
/// formato de monedas. Solo cambia el chrome visual.
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
          onPressed: () => context.popOrGo(RouteNames.admin),
        ),
        title: Text(l.adminMetricsTitle),
        actions: [
          // Selector de rango temporal — afecta a signups/mrr. Lo
          // mantenemos en el AppBar para que sea siempre visible
          // (alta-frecuencia de uso).
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
          constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
          child: overview.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppErrorState(
                message: l.adminMetricsLoadError,
                detail: e.toString(),
                onRetry: () =>
                    ref.invalidate(adminMetricsOverviewProvider),
                retryLabel: l.actionRetry,
              ),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: l.adminMetricsTitle,
            subtitle: l.adminMetricsHint,
          ),
          AppSpacing.gapMd,
          // ─── KPIs grid ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _KpiGrid(overview: overview),
          ),
          AppSpacing.gapLg,
          // ─── Signups chart ───
          _ChartSection(
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
          AppSpacing.gapMd,
          // ─── MRR chart ───
          _ChartSection(
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
          AppSpacing.gapMd,
          // ─── Plan distribution + Funnel side by side ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth > 800;
                final left = _ChartCard(
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
                );
                final right = _ChartCard(
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
                );
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: right),
                    ],
                  );
                }
                return Column(
                  children: [
                    left,
                    const SizedBox(height: AppSpacing.md),
                    right,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _chartError(BuildContext context, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
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

// ─────────────────────── KPI grid ───────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.overview});
  final MetricsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // 1 col mobile, 2 cols tablet, 4 cols desktop -- mismo
        // patron que home_page.dart.
        final int cols = w >= 900 ? 4 : (w >= 600 ? 2 : 1);
        const double gap = AppSpacing.md;
        final cardWidth = (w - gap * (cols - 1)) / cols;

        final cards = <Widget>[
          SizedBox(
            width: cardWidth,
            child: KpiCard(
              icon: Icons.people_alt_outlined,
              iconColor: const Color(0xFF3B82F6), // blue-500
              value: overview.totalUsers.toString(),
              label: l.adminMetricsKpiTotalUsers,
              trend: KpiTrend(
                delta: overview.newUsers30d.toDouble(),
                isPositive: overview.newUsers30d >= 0,
                suffix: '',
              ),
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: KpiCard(
              icon: Icons.workspace_premium_outlined,
              iconColor: const Color(0xFF10B981), // emerald-500
              value: overview.payingTenants.toString(),
              label: l.adminMetricsKpiPayingTenants,
              trend: KpiTrend(
                delta: overview.conversionPct,
                isPositive: overview.conversionPct > 0,
                suffix: '%',
              ),
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: KpiCard(
              icon: Icons.trending_up_outlined,
              iconColor: const Color(0xFF8B5CF6), // violet-500
              value: _formatMoneyCents(overview.mrrCents),
              label: l.adminMetricsKpiMrr,
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: KpiCard(
              icon: Icons.shopping_bag_outlined,
              iconColor: const Color(0xFFF59E0B), // amber-500
              value: overview.activeSubs.toString(),
              label: l.adminMetricsKpiActiveSubs,
              // Churn como trend negativo si > 0.
              trend: overview.churned30d > 0
                  ? KpiTrend(
                      delta: overview.churned30d.toDouble(),
                      isPositive: false,
                      suffix: '',
                    )
                  : null,
            ),
          ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards,
        );
      },
    );
  }

  String _formatMoneyCents(int cents) {
    final eur = cents / 100;
    if (eur >= 1000) return '${(eur / 1000).toStringAsFixed(1)}k €';
    return '${eur.toStringAsFixed(2)} €';
  }
}

// ─────────────────────── Chart wrappers ───────────────────────

/// Seccion full-width: PremiumCard horizontal con header arriba y el
/// chart abajo. Para los 2 charts grandes (Signups, MRR).
class _ChartSection extends StatelessWidget {
  const _ChartSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: PremiumCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: title,
              subtitle: subtitle,
              compact: true,
            ),
            AppSpacing.gapMd,
            child,
          ],
        ),
      ),
    );
  }
}

/// Card sin padding lateral exterior. Para los 2 charts de la fila
/// inferior (plan distribution + funnel) que viven dentro de un Row
/// con su propio padding.
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
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: title,
            subtitle: subtitle,
            compact: true,
          ),
          AppSpacing.gapMd,
          child,
        ],
      ),
    );
  }
}
