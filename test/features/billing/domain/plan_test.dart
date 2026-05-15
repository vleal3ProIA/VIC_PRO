import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/billing/domain/plan.dart';

void main() {
  group('Plan.fromMap', () {
    test('parses all fields', () {
      final p = Plan.fromMap(const {
        'id': 'plan-1',
        'slug': 'pro',
        'name': 'Pro',
        'description': 'Best for teams',
        'price_monthly_cents': 1900,
        'price_yearly_cents': 19000,
        'currency': 'EUR',
        'features': {'max_members': 25, 'sso': true},
        'position': 20,
        'is_active': true,
      });
      expect(p.id, 'plan-1');
      expect(p.slug, 'pro');
      expect(p.priceMonthlyCents, 1900);
      expect(p.features['max_members'], 25);
      expect(p.features['sso'], isTrue);
    });

    test('defaults currency to EUR, features to {}, is_active to true', () {
      final p = Plan.fromMap(const {
        'id': 'x',
        'slug': 'x',
        'name': 'X',
      });
      expect(p.currency, 'EUR');
      expect(p.features, isEmpty);
      expect(p.isActive, isTrue);
    });
  });

  group('formatPrice', () {
    Plan p({int? m, int? y, String currency = 'EUR'}) => Plan.fromMap({
          'id': 'p',
          'slug': 's',
          'name': 'n',
          'price_monthly_cents': m,
          'price_yearly_cents': y,
          'currency': currency,
        });

    test('Free → "Free"', () {
      expect(p(m: 0, y: 0).formatPrice(yearly: false), 'Free');
    });

    test('null price → "—" (custom pricing)', () {
      expect(p().formatPrice(yearly: false), '—');
    });

    test('1900 cents → "€19"', () {
      expect(p(m: 1900).formatPrice(yearly: false), '€19');
    });

    test('19000 cents yearly → "€190"', () {
      expect(p(y: 19000).formatPrice(yearly: true), '€190');
    });

    test('USD currency uses dollar sign', () {
      expect(p(m: 1900, currency: 'USD').formatPrice(yearly: false), r'$19');
    });

    test('Non-integer euros formatted with 2 decimals', () {
      expect(p(m: 1950).formatPrice(yearly: false), '€19.50');
    });
  });

  test('isCustomPriced when both prices null', () {
    final p = Plan.fromMap(const {
      'id': 'p',
      'slug': 'enterprise',
      'name': 'Enterprise',
    });
    expect(p.isCustomPriced, isTrue);
    expect(p.isFree, isFalse);
  });

  test('isFree when both prices are 0', () {
    final p = Plan.fromMap(const {
      'id': 'p',
      'slug': 'free',
      'name': 'Free',
      'price_monthly_cents': 0,
      'price_yearly_cents': 0,
    });
    expect(p.isFree, isTrue);
    expect(p.isCustomPriced, isFalse);
  });
}
