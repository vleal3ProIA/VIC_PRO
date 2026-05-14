import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/domain/entities/profile.dart';

/// Cuando el perfil del usuario carga (tras login / al arrancar con sesión),
/// aplica su `locale` y `theme_mode` guardados en BD a los notifiers
/// locales. Así las preferencias siguen al usuario entre dispositivos.
///
/// No genera bucles: `setLocale` / `setMode` solo escriben en
/// `SharedPreferences`. La escritura a BD ocurre exclusivamente desde
/// `ProfileSettingsNotifier`.
class ProfilePreferencesSync extends ConsumerWidget {
  const ProfilePreferencesSync({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<Profile?>>(myProfileProvider, (prev, next) {
      final profile = next.valueOrNull;
      if (profile == null) return;

      // Idioma: solo aplicar si difiere del override actual.
      final currentOverride = ref.read(localeNotifierProvider);
      if (currentOverride?.languageCode != profile.locale) {
        ref
            .read(localeNotifierProvider.notifier)
            .setLocale(profile.localeObj);
      }

      // Tema: solo aplicar si difiere.
      final currentTheme = ref.read(themeNotifierProvider);
      if (currentTheme != profile.themeModeEnum) {
        ref
            .read(themeNotifierProvider.notifier)
            .setMode(profile.themeModeEnum);
      }
    });

    return child;
  }
}
