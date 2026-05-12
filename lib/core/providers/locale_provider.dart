import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/providers/preferences_provider.dart';

/// Override del idioma elegido manualmente por el usuario.
/// - `null`  → seguir el idioma del sistema (con fallback `en` si no soportado).
/// - `Locale`→ idioma forzado por el usuario, persistido localmente y, cuando
///   esté autenticado, también en `profiles.locale` (lo haremos en la fase
///   del panel privado).
class LocaleNotifier extends Notifier<Locale?> {
  static const _key = 'user_locale_override';

  @override
  Locale? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getString(_key);
    if (stored == null || stored.isEmpty) return null;
    return Locale(stored);
  }

  Future<void> setLocale(Locale? locale) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (locale == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, locale.languageCode);
    }
    state = locale;
  }

  Future<void> clear() => setLocale(null);
}

final localeNotifierProvider =
    NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

/// Resuelve el locale efectivo: override del usuario > sistema (si soportado)
/// > fallback (`en`). Usado por `MaterialApp.locale`.
final effectiveLocaleProvider = Provider<Locale>((ref) {
  final override = ref.watch(localeNotifierProvider);
  if (override != null) return override;
  final system = WidgetsBinding.instance.platformDispatcher.locale;
  return AppLocales.resolve(system);
});
