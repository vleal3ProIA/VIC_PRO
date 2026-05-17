import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/admin_metrics/domain/admin_metrics.dart';

void main() {
  group('MetricsOverview.fromMap', () {
    test('parses all fields', () {
      final o = MetricsOverview.fromMap(const {
        'total_users': 1234,
        'verified_users': 1000,
        'new_users_30d': 50,
        'active_subs': 800,
        'paying_tenants': 200,
        'churned_30d': 15,
        'mrr_cents': 1234500,
        'arr_cents': 14814000,
        'conversion_pct': 16.2,
      });
      expect(o.totalUsers, 1234);
      expect(o.verifiedUsers, 1000);
      expect(o.newUsers30d, 50);
      expect(o.payingTenants, 200);
      expect(o.mrrCents, 1234500);
      expect(o.arrCents, 14814000);
      expect(o.conversionPct, 16.2);
    });

    test('handles missing fields with zeros', () {
      final o = MetricsOverview.fromMap(const <String, dynamic>{});
      expect(o.totalUsers, 0);
      expect(o.mrrCents, 0);
      expect(o.conversionPct, 0);
    });
  });

  group('MetricPoint', () {
    test('fromSignupsRow parses day + count', () {
      final p = MetricPoint.fromSignupsRow(const {
        'day': '2026-05-15',
        'count': 12,
      });
      expect(p.day.year, 2026);
      expect(p.day.month, 5);
      expect(p.day.day, 15);
      expect(p.value, 12.0);
    });

    test('fromMrrRow parses day + mrr_cents', () {
      final p = MetricPoint.fromMrrRow(const {
        'day': '2026-05-15',
        'mrr_cents': 123456,
      });
      expect(p.day.day, 15);
      expect(p.value, 123456.0);
    });
  });

  group('PlanDistributionRow', () {
    test('parses row', () {
      final r = PlanDistributionRow.fromMap(const {
        'slug': 'pro',
        'name': 'Pro',
        'count': 42,
        'mrr_cents': 84000,
      });
      expect(r.slug, 'pro');
      expect(r.name, 'Pro');
      expect(r.count, 42);
      expect(r.mrrCents, 84000);
    });

    test('handles missing fields with fallbacks', () {
      final r = PlanDistributionRow.fromMap(const <String, dynamic>{});
      expect(r.slug, 'unknown');
      expect(r.name, 'Unknown');
      expect(r.count, 0);
      expect(r.mrrCents, 0);
    });
  });

  group('MetricsFunnel', () {
    test('parses 4 steps', () {
      final f = MetricsFunnel.fromMap(const {
        'signups': 1000,
        'verified': 850,
        'with_active_sub': 600,
        'paying': 200,
      });
      expect(f.signups, 1000);
      expect(f.verified, 850);
      expect(f.withActiveSub, 600);
      expect(f.paying, 200);
    });

    test('conversionFrom returns fraction clamped 0..1', () {
      const f = MetricsFunnel(
        signups: 1000,
        verified: 0,
        withActiveSub: 0,
        paying: 200,
      );
      expect(f.conversionFrom(1000), 0.2);
      expect(f.conversionFrom(0), 0);
    });
  });

  group('MetricsRange', () {
    test('each range maps to its day count', () {
      expect(MetricsRange.d7.days, 7);
      expect(MetricsRange.d30.days, 30);
      expect(MetricsRange.d90.days, 90);
      expect(MetricsRange.d365.days, 365);
    });
  });
}
