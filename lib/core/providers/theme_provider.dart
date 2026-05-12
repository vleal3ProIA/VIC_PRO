import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/preferences_provider.dart';

/// Modo de tema elegido por el usuario.
/// - `ThemeMode.system` (default): seguir el modo del sistema operativo.
/// - `light` / `dark`: forzado por el usuario.
///
/// Persistencia local en `SharedPreferences`. Cuando exista panel privado,
/// también se sincronizará con `profiles.theme_mode` en Supabase.
class ThemeNotifier extends Notifier<ThemeMode> {
  static const _key = 'user_theme_mode';

  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getString(_key);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_key, mode.name);
    state = mode;
  }

  /// Toggle simple: system → light → dark → system…
  Future<void> cycle() async {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setMode(next);
  }
}

final themeNotifierProvider =
    NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);
