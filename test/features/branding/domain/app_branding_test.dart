import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/branding/domain/app_branding.dart';

void main() {
  group('AppBranding.fromMap', () {
    test('parses a fully populated row', () {
      final b = AppBranding.fromMap(const {
        'commercial_name': 'Acme Inc',
        'tagline': 'We sell anvils',
        'support_email': 'hi@acme.example',
        'website_url': 'https://acme.example',
        'logo_url': 'https://cdn.acme/logo.png',
        'logo_dark_url': 'https://cdn.acme/logo-dark.png',
        'favicon_url': 'https://cdn.acme/favicon.ico',
        'og_image_url': 'https://cdn.acme/og.png',
        'color_palette': 'purple',
        'setup_completed': true,
        'registration_enabled': true,
        'updated_at': '2026-05-15T10:00:00Z',
      });
      expect(b.commercialName, 'Acme Inc');
      expect(b.tagline, 'We sell anvils');
      expect(b.supportEmail, 'hi@acme.example');
      expect(b.colorPalette, 'purple');
      expect(b.setupCompleted, isTrue);
      expect(b.registrationEnabled, isTrue);
      expect(b.faviconUrl, 'https://cdn.acme/favicon.ico');
    });

    test('falls back to "myapp" when commercial_name is empty', () {
      final b = AppBranding.fromMap(const {
        'commercial_name': '',
        'color_palette': 'blue',
        'setup_completed': false,
        'registration_enabled': false,
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(b.commercialName, 'myapp');
    });

    test('falls back to "myapp" when commercial_name is null', () {
      final b = AppBranding.fromMap(const {
        'color_palette': 'blue',
        'setup_completed': false,
        'registration_enabled': false,
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(b.commercialName, 'myapp');
    });

    test('converts empty optional strings to null', () {
      final b = AppBranding.fromMap(const {
        'commercial_name': 'X',
        'tagline': '',
        'support_email': '   ',
        'website_url': 'https://x.com',
        'color_palette': 'blue',
        'setup_completed': false,
        'registration_enabled': false,
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(b.tagline, isNull);
      expect(b.supportEmail, isNull);
      expect(b.websiteUrl, 'https://x.com');
    });

    test('default palette = blue when missing', () {
      final b = AppBranding.fromMap(const {
        'commercial_name': 'X',
        'setup_completed': false,
        'registration_enabled': false,
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(b.colorPalette, 'blue');
    });

    test('flags default to false when null', () {
      final b = AppBranding.fromMap(const {
        'commercial_name': 'X',
        'color_palette': 'blue',
        'updated_at': '2026-05-01T10:00:00Z',
      });
      expect(b.setupCompleted, isFalse);
      expect(b.registrationEnabled, isFalse);
    });
  });

  group('logo helpers', () {
    AppBranding withLogos({String? light, String? dark}) {
      return AppBranding(
        commercialName: 'X',
        colorPalette: 'blue',
        setupCompleted: true,
        registrationEnabled: false,
        logoUrl: light,
        logoDarkUrl: dark,
      );
    }

    test('hasLogoFor light: needs light logo', () {
      expect(withLogos(light: 'a').hasLogoFor(isDark: false), isTrue);
      expect(withLogos(dark: 'a').hasLogoFor(isDark: false), isFalse);
      expect(withLogos().hasLogoFor(isDark: false), isFalse);
    });

    test('hasLogoFor dark: accepts either dark or light as fallback', () {
      expect(withLogos(dark: 'a').hasLogoFor(isDark: true), isTrue);
      expect(withLogos(light: 'a').hasLogoFor(isDark: true), isTrue);
      expect(withLogos().hasLogoFor(isDark: true), isFalse);
    });

    test('logoFor dark prefers dark variant', () {
      expect(
        withLogos(light: 'L', dark: 'D').logoFor(isDark: true),
        'D',
      );
    });

    test('logoFor dark falls back to light when no dark', () {
      expect(withLogos(light: 'L').logoFor(isDark: true), 'L');
    });
  });

  test('fallback constant has sane defaults', () {
    expect(AppBranding.fallback.commercialName, 'myapp');
    expect(AppBranding.fallback.colorPalette, 'blue');
    expect(AppBranding.fallback.setupCompleted, isFalse);
    expect(AppBranding.fallback.registrationEnabled, isFalse);
  });
}
