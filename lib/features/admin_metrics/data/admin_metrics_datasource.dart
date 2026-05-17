import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/admin_metrics.dart';

/// Acceso a las RPCs admin_metrics_*. Admin-only via RLS interno de
/// cada RPC. Si el llamante no es admin, las RPCs lanzan `admin only`
/// y el cliente lo recibe como PostgrestException.
class AdminMetricsDataSource {
  const AdminMetricsDataSource(this._client);

  final SupabaseClient _client;

  Future<MetricsOverview> overview() async {
    final data = await _client.rpc<dynamic>('admin_metrics_overview');
    return MetricsOverview.fromMap(
      (data as Map).cast<String, dynamic>(),
    );
  }

  Future<List<MetricPoint>> signups({int days = 30}) async {
    final data = await _client.rpc<dynamic>(
      'admin_metrics_signups',
      params: {'p_days': days},
    );
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(MetricPoint.fromSignupsRow)
        .toList(growable: false);
  }

  Future<List<MetricPoint>> mrr({int days = 30}) async {
    final data = await _client.rpc<dynamic>(
      'admin_metrics_mrr',
      params: {'p_days': days},
    );
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(MetricPoint.fromMrrRow)
        .toList(growable: false);
  }

  Future<List<PlanDistributionRow>> planDistribution() async {
    final data =
        await _client.rpc<dynamic>('admin_metrics_plan_distribution');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(PlanDistributionRow.fromMap)
        .toList(growable: false);
  }

  Future<MetricsFunnel> funnel() async {
    final data = await _client.rpc<dynamic>('admin_metrics_funnel');
    return MetricsFunnel.fromMap(
      (data as Map).cast<String, dynamic>(),
    );
  }
}
