import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/extensions/string_extensions.dart';

void main() {
  group('StringX', () {
    test('isValidEmail accepts well-formed emails', () {
      expect('user@example.com'.isValidEmail, isTrue);
      expect('john.doe+filter@sub.domain.io'.isValidEmail, isTrue);
    });

    test('isValidEmail rejects malformed emails', () {
      expect('not-an-email'.isValidEmail, isFalse);
      expect('@nodomain.com'.isValidEmail, isFalse);
      expect('user@'.isValidEmail, isFalse);
    });
  });

  group('AppLocales.resolve', () {
    test('returns user system locale when supported', () {
      expect(AppLocales.resolve(const Locale('es')), const Locale('es'));
      expect(AppLocales.resolve(const Locale('uk')), const Locale('uk'));
    });

    test('falls back to English when not supported', () {
      expect(AppLocales.resolve(const Locale('zh')), AppLocales.fallback);
      expect(AppLocales.resolve(const Locale('ja')), AppLocales.fallback);
    });

    test('falls back to English when locale is null', () {
      expect(AppLocales.resolve(null), AppLocales.fallback);
    });
  });
}
