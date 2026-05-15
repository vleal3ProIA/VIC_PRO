import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/billing/domain/entitlements.dart';

void main() {
  group('Entitlements.quota', () {
    test('reads int values', () {
      final e = Entitlements({'max_members': 25, 'storage': 100});
      expect(e.quota('max_members'), 25);
      expect(e.quota('storage'), 100);
    });

    test('falls back when key missing', () {
      final e = Entitlements({});
      expect(e.quota('max_members', fallback: 3), 3);
    });

    test('coerces num → int', () {
      final e = Entitlements({'k': 1.0});
      expect(e.quota('k'), 1);
    });
  });

  group('Entitlements.capability', () {
    test('reads bool', () {
      final e = Entitlements({'sso': true, 'wl': false});
      expect(e.capability('sso'), isTrue);
      expect(e.capability('wl'), isFalse);
    });

    test('falls back when missing or wrong type', () {
      final e = Entitlements({'sso': 'yes'});
      expect(e.capability('sso'), isFalse);
      expect(e.capability('missing', fallback: true), isTrue);
    });
  });

  group('Entitlements.allows', () {
    test('current < max → true', () {
      final e = Entitlements({'max_members': 5});
      expect(e.allows('max_members', current: 4), isTrue);
    });

    test('current == max → false (at limit)', () {
      final e = Entitlements({'max_members': 5});
      expect(e.allows('max_members', current: 5), isFalse);
      expect(e.atOrOverLimit('max_members', current: 5), isTrue);
    });

    test('-1 means unlimited', () {
      final e = Entitlements({'max_members': -1});
      expect(e.allows('max_members', current: 99999), isTrue);
      expect(e.atOrOverLimit('max_members', current: 99999), isFalse);
    });

    test('missing key uses fallback', () {
      final e = Entitlements({});
      expect(e.allows('max_members', current: 0, fallback: 0), isFalse);
      expect(e.allows('max_members', current: 0, fallback: 5), isTrue);
    });
  });

  test('Entitlements.empty is empty', () {
    expect(const Entitlements.empty().raw, isEmpty);
  });

  test('Entitlements.choice reads strings', () {
    final e = Entitlements({'support': 'priority', 'wrong': 5});
    expect(e.choice('support'), 'priority');
    expect(e.choice('wrong'), isNull);
    expect(e.choice('missing'), isNull);
  });
}
