import 'package:flutter/material.dart';

/// 8 idiomas oficiales del proyecto. El orden aquí es el orden en el que
/// aparecen en el selector de idioma.
class AppLocales {
  AppLocales._();

  static const Locale es = Locale('es');
  static const Locale en = Locale('en');
  static const Locale de = Locale('de');
  static const Locale fr = Locale('fr');
  static const Locale it = Locale('it');
  static const Locale pt = Locale('pt');
  static const Locale ru = Locale('ru');
  static const Locale uk = Locale('uk');

  static const List<Locale> all = [es, en, de, fr, it, pt, ru, uk];

  /// Fallback obligatorio cuando el idioma del sistema no está soportado.
  static const Locale fallback = en;

  /// Nombre nativo para mostrar en el selector.
  static const Map<String, String> nativeName = {
    'es': 'Español',
    'en': 'English',
    'de': 'Deutsch',
    'fr': 'Français',
    'it': 'Italiano',
    'pt': 'Português',
    'ru': 'Русский',
    'uk': 'Українська',
  };

  /// Emoji de bandera para el selector.
  static const Map<String, String> flag = {
    'es': '🇪🇸',
    'en': '🇬🇧',
    'de': '🇩🇪',
    'fr': '🇫🇷',
    'it': '🇮🇹',
    'pt': '🇵🇹',
    'ru': '🇷🇺',
    'uk': '🇺🇦',
  };

  /// Resuelve el locale del sistema al soportado más cercano. Si el idioma
  /// del sistema no está, devuelve el fallback (inglés).
  static Locale resolve(Locale? systemLocale) {
    if (systemLocale == null) return fallback;
    final match = all.where(
      (l) => l.languageCode == systemLocale.languageCode,
    );
    return match.isNotEmpty ? match.first : fallback;
  }
}
