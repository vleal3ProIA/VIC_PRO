import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/billing/domain/entitlements.dart';

void main() {
  group('Entitlements.quota', () {
    test('reads int values', () {
      const e = Entitlements( {'max_members': 25, 'storage': 100});
      expect(e.quota('max_members'), 25);
      expect(e.quota('storage'), 100);
    });

    test('falls back when key missing', () {
      const e = Entitlements( {});
      expect(e.quota('max_members', fallback: 3), 3);
    });

    test('coerces num → int', () {
      const e = Entitlements( {'k': 1.0});
      expect(e.quota('k'), 1);
    });
  });

  group('Entitlements.capability', () {
    test('reads bool', () {
      const e = Entitlements( {'sso': true, 'wl': false});
      expect(e.capability('sso'), isTrue);
      expect(e.capability('wl'), isFalse);
    });

    test('falls back when missing or wrong type', () {
      const e = Entitlements( {'sso': 'yes'});
      expect(e.capability('sso'), isFalse);
      expect(e.capability('missing', fallback: true), isTrue);
    });
  });

  group('Entitlements.allows', () {
    test('current < max → true', () {
      const e = Entitlements( {'max_members': 5});
      expect(e.allows('max_members', current: 4), isTrue);
    });

    test('current == max → false (at limit)', () {
      const e = Entitlements( {'max_members': 5});
      expect(e.allows('max_members', current: 5), isFalse);
      expect(e.atOrOverLimit('max_members', current: 5), isTrue);
    });

    test('-1 means unlimited', () {
      const e = Entitlements( {'max_members': -1});
      expect(e.allows('max_members', current: 99999), isTrue);
      expect(e.atOrOverLimit('max_members', current: 99999), isFalse);
    });

    test('missing key uses fallback', () {
      const e = Entitlements( {});
      expect(e.allows('max_members', current: 0, fallback: 0), isFalse);
      expect(e.allows('max_members', current: 0, fallback: 5), isTrue);
    });
  });

  test('Entitlements.empty is empty', () {
    expect(const Entitlements.empty().raw, isEmpty);
  });

  test('Entitlements.choice reads strings', () {
    const e = Entitlements( {'support': 'priority', 'wrong': 5});
    expect(e.choice('support'), 'priority');
    expect(e.choice('wrong'), isNull);
    expect(e.choice('missing'), isNull);
  });
}
