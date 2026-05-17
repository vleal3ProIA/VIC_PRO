import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/config/env_config.dart';
import 'package:myapp/core/constants/app_constants.dart';
import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/observability/analytics_service.dart';
import 'package:myapp/core/observability/sentry_user_sync.dart';
import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/core/router/app_router.dart';
import 'package:myapp/core/theme/app_theme.dart';
import 'package:myapp/features/account/application/profile_preferences_sync.dart';
import 'package:myapp/features/branding/application/branding_providers.dart';
import 'package:myapp/features/branding/presentation/branding_palettes.dart';
import 'package:myapp/features/branding/presentation/widgets/document_branding_sync.dart';
import 'package:myapp/features/legal/presentation/widgets/cookie_consent_banner.dart';
import 'package:myapp/features/tenants/application/tenant_sentry_sync.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';
import 'package:responsive_framework/responsive_framework.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Side-effect-only: mantienen Sentry y Analytics sincronizados con la
    // sesión de Supabase y con el tenant activo.
    ref.watch(sentryUserSyncProvider);
    ref.watch(analyticsUserSyncProvider);
    ref.watch(tenantSentrySyncProvider);

    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeNotifierProvider);
    final locale = ref.watch(effectiveLocaleProvider);

    // Branding del deploy (nombre comercial, paleta). Usamos el helper
    // sin "loading state" — mientras carga usa el fallback (azul + "myapp")
    // y al hidratarse fuerza un rebuild con la paleta real.
    final branding = ref.watch(brandingOrFallbackProvider);
    final palette = BrandingPalettes.bySlug(branding.colorPalette);

    return MaterialApp.router(
      title: branding.commercialName.isNotEmpty
          ? branding.commercialName
          : AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightFor(palette),
      darkTheme: AppTheme.darkFor(palette),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocales.all,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      builder: (context, child) => DocumentBrandingSync(
        child: ProfilePreferencesSync(
        child: _EnvBanner(
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
        ),
      ),
    );
  }
}

/// Envuelve la app con un [Banner] en la esquina superior derecha cuando
/// el entorno NO es producción. En desarrollo dice "DEV" en gris/azul; en
/// staging dice "STAGING" en amarillo intenso. Imposible confundir el
/// entorno antes de un click destructivo (cancelar suscripción, borrar
/// cuenta, etc.).
///
/// El widget es no-op en producción (devuelve el child tal cual) para no
/// añadir overhead innecesario.
class _EnvBanner extends StatelessWidget {
  const _EnvBanner({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (EnvConfig.isProduction) return child;
    final (label, color) = EnvConfig.isStaging
        ? ('STAGING', const Color(0xFFFFA000))
        : ('DEV', const Color(0xFF3949AB));
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Banner(
        message: label,
        location: BannerLocation.topEnd,
        color: color,
        child: child,
      ),
    );
  }
}
