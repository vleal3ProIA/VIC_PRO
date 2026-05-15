import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Monta [child] dentro de una `MaterialApp.router` mínima con todo lo que
/// los widgets de la app dan por sentado:
///
/// - `ProviderScope` con [overrides] (más `sharedPreferencesProvider`
///   inicializado con un mock).
/// - Soporte de i18n forzado a inglés para que los tests sean estables
///   independientemente del entorno.
/// - Un `GoRouter` stub con todas las rutas a las que las pantallas pueden
///   navegar (los destinos son `Scaffold` vacíos): así `context.goNamed(...)`
///   no explota en los tests.
///
/// Devuelve el `WidgetTester` listo. Llama a `tester.pump()` extra si
/// necesitas que termine algún microtask de `_load()`.
Future<void> pumpForTest(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  // Pantallas largas (login con 4-5 botones extra ≈ 1000 px de alto).
  // Hacemos la superficie de test grande para que NO desborde durante el
  // render.
  await tester.binding.setSurfaceSize(const Size(900, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  Widget emptyScaffold(BuildContext _, GoRouterState __) => const Scaffold();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        name: 'root',
        builder: (_, __) => Scaffold(body: child),
      ),
      // Stubs *nombrados* — necesarios para que `context.goNamed('foo')`
      // resuelva. Las pruebas no comprueban navegación; verificamos efectos
      // del notifier.
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
      GoRoute(
        path: '/verify-email-sent',
        name: 'verify_email_sent',
        builder: emptyScaffold,
      ),
      GoRoute(path: '/terms', name: 'terms', builder: emptyScaffold),
      GoRoute(path: '/privacy', name: 'privacy', builder: emptyScaffold),
      GoRoute(path: '/cookies', name: 'cookies', builder: emptyScaffold),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Sin Supabase real en tests: el logger no toca BD.
        auditLoggerProvider.overrideWithValue(const AuditLogger.noop()),
        ...overrides,
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        supportedLocales: AppLocales.all,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  // Permite que cualquier `Future.microtask`-on-build (p. ej. el _load de
  // algunos notifiers) se asiente antes de inspeccionar la UI.
  await tester.pump();
  await tester.pump();
}
