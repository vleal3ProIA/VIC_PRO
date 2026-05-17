import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/seo/seo_meta.dart';

void main() {
  group('SeoMeta', () {
    test('stores all fields', () {
      const m = SeoMeta(
        title: 'My App',
        description: 'Best app ever',
        ogImageUrl: 'https://x.com/og.png',
        canonical: 'https://x.com',
      );
      expect(m.title, 'My App');
      expect(m.description, 'Best app ever');
      expect(m.ogImageUrl, 'https://x.com/og.png');
      expect(m.canonical, 'https://x.com');
    });

    test('copyWith partial updates', () {
      const original = SeoMeta(
        title: 'A',
        description: 'B',
        ogImageUrl: 'C',
        canonical: 'D',
      );
      final updated = original.copyWith(title: 'AA', canonical: 'DD');
      expect(updated.title, 'AA');
      expect(updated.description, 'B');
      expect(updated.ogImageUrl, 'C');
      expect(updated.canonical, 'DD');
    });

    test('copyWith with no args returns equivalent values', () {
      const original = SeoMeta(
        title: 'A',
        description: 'B',
      );
      final clone = original.copyWith();
      expect(clone.title, 'A');
      expect(clone.description, 'B');
    });
  });
}
