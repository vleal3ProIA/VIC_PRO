import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/domain/entities/profile.dart';

/// Sincroniza las preferencias (idioma, tema) entre el perfil del usuario y
/// los notifiers locales:
///
/// - Cuando el perfil carga (tras login / al arrancar con sesión) aplica su
///   `locale` y `theme_mode` guardados.
/// - Cuando el usuario cierra sesión, **limpia el override de idioma**: el
///   estado "sin sesión" debe seguir el idioma del SISTEMA, no arrastrar el
///   del último usuario. Sin esto, la sesión transitoria que el SDK crea al
///   abrir el enlace de verificación de email dejaba el idioma "pegado" (a
///   menudo en inglés) en el login y el registro.
///
/// No genera bucles: `setLocale` / `setMode` solo escriben en
/// `SharedPreferences`. La escritura a BD ocurre exclusivamente desde
/// `ProfileSettingsNotifier`.
class ProfilePreferencesSync extends ConsumerWidget {
  const ProfilePreferencesSync({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Logout → volver al idioma del sistema.
    ref.listen<bool>(isAuthenticatedProvider, (prev, next) {
      final wasAuthed = prev ?? false;
      if (wasAuthed && !next) {
        ref.read(localeNotifierProvider.notifier).clear();
      }
    });

    ref.listen<AsyncValue<Profile?>>(myProfileProvider, (prev, next) {
      final profile = next.valueOrNull;
      if (profile == null) return;

      // Idioma: solo aplicar si el idioma EFECTIVO (override o sistema)
      // difiere del guardado. Comparar contra el efectivo —y no contra el
      // override— evita forzar un override redundante (y el rebuild de
      // MaterialApp que conlleva) cuando el usuario ya está viendo el
      // idioma correcto a través del locale del sistema.
      final currentEffective = ref.read(effectiveLocaleProvider);
      if (currentEffective.languageCode != profile.locale) {
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
