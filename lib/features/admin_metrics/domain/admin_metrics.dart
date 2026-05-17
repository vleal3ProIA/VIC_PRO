import 'package:meta/meta.dart';

/// Cards principales del dashboard `/admin/metrics`. Devuelve la RPC
/// `admin_metrics_overview` en un solo round-trip.
@immutable
class MetricsOverview {
  const MetricsOverview({
    required this.totalUsers,
    required this.verifiedUsers,
    required this.newUsers30d,
    required this.activeSubs,
    required this.payingTenants,
    required this.churned30d,
    required this.mrrCents,
    required this.arrCents,
    required this.conversionPct,
  });

  factory MetricsOverview.fromMap(Map<String, dynamic> m) {
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    int big(String k) => (m[k] as num?)?.toInt() ?? 0;
    return MetricsOverview(
      totalUsers: i('total_users'),
      verifiedUsers: i('verified_users'),
      newUsers30d: i('new_users_30d'),
      activeSubs: i('active_subs'),
      payingTenants: i('paying_tenants'),
      churned30d: i('churned_30d'),
      mrrCents: big('mrr_cents'),
      arrCents: big('arr_cents'),
      conversionPct: (m['conversion_pct'] as num?)?.toDouble() ?? 0,
    );
  }

  final int totalUsers;
  final int verifiedUsers;
  final int newUsers30d;
  final int activeSubs;
  final int payingTenants;
  final int churned30d;
  final int mrrCents;
  final int arrCents;
  final double conversionPct;
}

/// Un punto en una serie temporal (fecha + valor numérico).
@immutable
class MetricPoint {
  const MetricPoint({required this.day, required this.value});

  factory MetricPoint.fromSignupsRow(Map<String, dynamic> m) {
    return MetricPoint(
      day: DateTime.parse(m['day'] as String),
      value: (m['count'] as num).toDouble(),
    );
  }

  factory MetricPoint.fromMrrRow(Map<String, dynamic> m) {
    return MetricPoint(
      day: DateTime.parse(m['day'] as String),
      value: (m['mrr_cents'] as num).toDouble(),
    );
  }

  final DateTime day;
  final double value;
}

/// Una fila de la distribución por plan.
@immutable
class PlanDistributionRow {
  const PlanDistributionRow({
    required this.slug,
    required this.name,
    required this.count,
    required this.mrrCents,
  });

  factory PlanDistributionRow.fromMap(Map<String, dynamic> m) {
    return PlanDistributionRow(
      slug: m['slug'] as String? ?? 'unknown',
      name: m['name'] as String? ?? 'Unknown',
      count: (m['count'] as num?)?.toInt() ?? 0,
      mrrCents: (m['mrr_cents'] as num?)?.toInt() ?? 0,
    );
  }

  final String slug;
  final String name;
  final int count;
  final int mrrCents;
}

/// 4 etapas del funnel de conversión.
@immutable
class MetricsFunnel {
  const MetricsFunnel({
    required this.signups,
    required this.verified,
    required this.withActiveSub,
    required this.paying,
  });

  factory MetricsFunnel.fromMap(Map<String, dynamic> m) {
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    return MetricsFunnel(
      signups: i('signups'),
      verified: i('verified'),
      withActiveSub: i('with_active_sub'),
      paying: i('paying'),
    );
  }

  final int signups;
  final int verified;
  final int withActiveSub;
  final int paying;

  /// `0..1` — qué fracción del paso anterior llega aquí.
  double conversionFrom(int prev) {
    if (prev == 0) return 0;
    return (paying / prev).clamp(0, 1).toDouble();
  }
}

/// Conjunto de rangos disponibles en el selector de la UI.
enum MetricsRange {
  d7(7),
  d30(30),
  d90(90),
  d365(365);

  const MetricsRange(this.days);
  final int days;
}
