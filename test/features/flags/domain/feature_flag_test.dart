import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/flags/domain/feature_flag.dart';

void main() {
  group('FeatureFlag.fromMap', () {
    test('parses required fields', () {
      final f = FeatureFlag.fromMap(const {
        'key': 'new_dashboard',
        'enabled': true,
        'source': 'global',
        'value': null,
      });
      expect(f.key, 'new_dashboard');
      expect(f.enabled, isTrue);
      expect(f.source, FeatureFlagSource.global);
      expect(f.value, isNull);
    });

    test('parses value when present', () {
      final f = FeatureFlag.fromMap(const {
        'key': 'limits',
        'enabled': true,
        'source': 'tenant',
        'value': {'max_uploads': 100, 'model': 'gpt-4'},
      });
      expect(f.value, isNotNull);
      expect(f.value!['max_uploads'], 100);
      expect(f.source, FeatureFlagSource.tenant);
    });

    test('defaults enabled to false when null', () {
      final f = FeatureFlag.fromMap(const {
        'key': 'k',
        'enabled': null,
        'source': 'rollout',
      });
      expect(f.enabled, isFalse);
    });
  });

  group('FeatureFlag.config', () {
    test('reads typed value with fallback', () {
      final f = FeatureFlag.fromMap(const {
        'key': 'limits',
        'enabled': true,
        'source': 'global',
        'value': {'max_uploads': 100},
      });
      expect(f.config<int>('max_uploads', 50), 100);
      expect(f.config<int>('missing', 50), 50);
      // Type mismatch → fallback.
      expect(f.config<String>('max_uploads', 'default'), 'default');
    });
  });

  group('FeatureFlagSource', () {
    test('fromString parses known values', () {
      expect(FeatureFlagSource.fromString('user'), FeatureFlagSource.user);
      expect(FeatureFlagSource.fromString('tenant'), FeatureFlagSource.tenant);
      expect(FeatureFlagSource.fromString('rollout'), FeatureFlagSource.rollout);
      expect(FeatureFlagSource.fromString('global'), FeatureFlagSource.global);
    });

    test('fromString defaults unknown to global', () {
      expect(FeatureFlagSource.fromString('???'), FeatureFlagSource.global);
    });
  });

  group('FeatureFlag equality', () {
    test('same key+enabled ⇒ equal', () {
      final a = FeatureFlag.fromMap(const {
        'key': 'x',
        'enabled': true,
        'source': 'user',
      });
      final b = FeatureFlag.fromMap(const {
        'key': 'x',
        'enabled': true,
        'source': 'global', // diferente source → sigue siendo equal
      });
      expect(a, equals(b));
    });

    test('different enabled ⇒ not equal', () {
      final a = FeatureFlag.fromMap(const {
        'key': 'x',
        'enabled': true,
        'source': 'user',
      });
      final b = FeatureFlag.fromMap(const {
        'key': 'x',
        'enabled': false,
        'source': 'user',
      });
      expect(a, isNot(equals(b)));
    });
  });

  group('FeatureFlagDefinition.fromMap', () {
    test('parses admin definition', () {
      final d = FeatureFlagDefinition.fromMap(const {
        'key': 'billing_v2',
        'description': 'New billing UX',
        'enabled': false,
        'rollout_percentage': 30,
        'value': null,
        'updated_at': '2026-05-15T10:00:00Z',
      });
      expect(d.key, 'billing_v2');
      expect(d.description, 'New billing UX');
      expect(d.enabled, isFalse);
      expect(d.rolloutPercentage, 30);
      expect(d.updatedAt.year, 2026);
    });
  });
}
