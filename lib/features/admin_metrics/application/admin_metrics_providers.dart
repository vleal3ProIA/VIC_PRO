import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/admin_metrics_datasource.dart';
import '../domain/admin_metrics.dart';

final adminMetricsDataSourceProvider =
    Provider<AdminMetricsDataSource>((ref) {
  return AdminMetricsDataSource(ref.watch(supabaseClientProvider));
});

/// Rango seleccionado en el dropdown del header — default 30 días.
final adminMetricsRangeProvider =
    StateProvider<MetricsRange>((_) => MetricsRange.d30);

/// Overview cards (4-5 KPIs grandes). Cambia solo si el admin pulsa
/// refresh, no depende del rango.
final adminMetricsOverviewProvider =
    FutureProvider<MetricsOverview>((ref) async {
  return ref.watch(adminMetricsDataSourceProvider).overview();
});

/// Signups por día — depende del rango seleccionado.
final adminMetricsSignupsProvider =
    FutureProvider<List<MetricPoint>>((ref) async {
  final range = ref.watch(adminMetricsRangeProvider);
  return ref
      .watch(adminMetricsDataSourceProvider)
      .signups(days: range.days);
});

/// MRR por día — depende del rango seleccionado.
final adminMetricsMrrProvider =
    FutureProvider<List<MetricPoint>>((ref) async {
  final range = ref.watch(adminMetricsRangeProvider);
  return ref.watch(adminMetricsDataSourceProvider).mrr(days: range.days);
});

/// Distribución por plan (snapshot actual, no afecta al rango).
final adminMetricsPlanDistributionProvider =
    FutureProvider<List<PlanDistributionRow>>((ref) async {
  return ref.watch(adminMetricsDataSourceProvider).planDistribution();
});

/// Funnel de conversión.
final adminMetricsFunnelProvider =
    FutureProvider<MetricsFunnel>((ref) async {
  return ref.watch(adminMetricsDataSourceProvider).funnel();
});
