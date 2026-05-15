import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/constants/app_constants.dart';
import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/observability/analytics_service.dart';
import 'package:myapp/core/observability/sentry_user_sync.dart';
import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/core/router/app_router.dart';
import 'package:myapp/core/theme/app_theme.dart';
import 'package:myapp/features/account/application/profile_preferences_sync.dart';
import 'package:myapp/features/legal/presentation/widgets/cookie_consent_banner.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';
import 'package:responsive_framework/responsive_framework.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Side-effect-only: mantienen Sentry y Analytics sincronizados con la
    // sesión de Supabase.
    ref.watch(sentryUserSyncProvider);
    ref.watch(analyticsUserSyncProvider);

    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeNotifierProvider);
    final locale = ref.watch(effectiveLocaleProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocales.all,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      builder: (context, child) => ProfilePreferencesSync(
        child: Stack(
          children: [
            ResponsiveBreakpoints.builder(
              child: child!,
              breakpoints: const [
                Breakpoint(start: 0, end: 600, name: MOBILE),
                Breakpoint(start: 601, end: 1024, name: TABLET),
                Breakpoint(start: 1025, end: 1440, name: DESKTOP),
                Breakpoint(start: 1441, end: double.infinity, name: '4K'),
              ],
            ),
            // Banner GDPR fijo abajo, sobre cualquier pantalla, hasta que
            // el usuario decida (acepta / rechaza / personaliza). El propio
            // widget se oculta cuando hay decisión, así que no hace falta
            // ningún flag aquí.
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CookieConsentBanner(),
            ),
          ],
        ),
      ),
    );
  }
}
