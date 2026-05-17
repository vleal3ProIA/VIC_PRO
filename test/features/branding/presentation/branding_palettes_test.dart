import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/branding/presentation/branding_palettes.dart';

void main() {
  group('BrandingPalettes', () {
    test('exposes the 5 curated palettes in stable order', () {
      final slugs = BrandingPalettes.all.map((p) => p.slug).toList();
      expect(slugs, ['blue', 'green', 'purple', 'orange', 'mono']);
    });

    test('bySlug returns the matching palette', () {
      expect(BrandingPalettes.bySlug('purple').slug, 'purple');
      expect(BrandingPalettes.bySlug('mono').label, 'Mono');
    });

    test('bySlug falls back to default for unknown slug', () {
      final p = BrandingPalettes.bySlug('unicorn');
      expect(p.slug, 'blue');
    });

    test('bySlug falls back to default for empty slug', () {
      expect(BrandingPalettes.bySlug('').slug, 'blue');
    });

    test('every palette has light and dark schemes', () {
      for (final p in BrandingPalettes.all) {
        expect(p.lightScheme.primary, isNotNull,
            reason: '${p.slug} missing light primary');
        expect(p.darkScheme.primary, isNotNull,
            reason: '${p.slug} missing dark primary');
      }
    });

    test('every palette has a non-transparent preview color', () {
      for (final p in BrandingPalettes.all) {
        expect(p.previewColor.a, 1.0, reason: '${p.slug} preview transparent');
      }
    });

    test('fallback matches the first listed palette', () {
      expect(BrandingPalettes.fallback.slug, BrandingPalettes.all.first.slug);
    });
  });
}
