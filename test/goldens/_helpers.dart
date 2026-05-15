import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tamaños de viewport en los que validamos goldens.
///
/// `mobile` ≈ iPhone 13 pro vertical; `desktop` ≈ portátil 1280 px.
/// Capturar ambos protege contra romper el layout responsive sin querer.
final goldenDevices = <Device>[
  const Device(
    name: 'mobile',
    size: Size(390, 844),
  ),
  const Device(
    name: 'desktop',
    size: Size(1280, 800),
  ),
];

/// Monta [child] dentro de una `MaterialApp.router` mínima preparada para
/// **goldens** (regresión visual).
///
/// Diferencias respecto a `pumpForTest`:
/// - Devuelve el `Widget` listo para pasar a `multiScreenGolden` /
///   `screenMatchesGolden` (no llama a `pumpWidget` por nosotros).
/// - Locale fijado a inglés para que los goldens no dependan del idioma del
///   sistema.
/// - No fuerza un surface size: lo controla `multiScreenGolden` por device.
Widget buildForGolden({
  required Widget child,
  List<Override> overrides = const [],
}) {
  Widget emptyScaffold(BuildContext _, GoRouterState __) => const Scaffold();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        name: 'root',
        builder: (_, __) => Scaffold(body: child),
      ),
      // Stubs nombrados — necesarios para que `context.goNamed(...)` no
      // explote al renderizar (los TextButton del footer, etc.).
      GoRoute(path: '/login', name: 'login', builder: emptyScaffold),
      GoRoute(path: '/register', name: 'register', builder: emptyScaffold),
      GoRoute(path: '/home', name: 'home', builder: emptyScaffold),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot_password',
        builder: emptyScaffold,
      ),
      GoRoute(path: '/magic-link', name: 'magic_link', builder: emptyScaffold),
      GoRoute(path: '/otp', name: 'otp_request', builder: emptyScaffold),
      GoRoute(path: '/terms', name: 'terms', builder: emptyScaffold),
      GoRoute(path: '/privacy', name: 'privacy', builder: emptyScaffold),
      GoRoute(path: '/cookies', name: 'cookies', builder: emptyScaffold),
      GoRoute(path: '/welcome', name: 'welcome', builder: emptyScaffold),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: AppLocales.all,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    ),
  );
}

/// Crea los overrides de Riverpod que un golden necesita por defecto:
/// SharedPreferences con valores mock + AuditLogger no-op.
Future<List<Override>> defaultGoldenOverrides() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    auditLoggerProvider.overrideWithValue(const AuditLogger.noop()),
  ];
}
