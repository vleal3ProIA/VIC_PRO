import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:myapp/features/auth/presentation/pages/login_page.dart';
import 'package:myapp/features/auth/presentation/pages/magic_link_page.dart';
import 'package:myapp/features/auth/presentation/pages/otp_request_page.dart';
import 'package:myapp/features/auth/presentation/pages/register_page.dart';
import 'package:myapp/features/auth/presentation/pages/verify_email_sent_page.dart';
import 'package:myapp/features/legal/presentation/pages/cookies_page.dart';
import 'package:myapp/features/legal/presentation/pages/privacy_page.dart';
import 'package:myapp/features/legal/presentation/pages/terms_page.dart';
import 'package:myapp/features/welcome/presentation/pages/welcome_page.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/application/fakes.dart';

/// Re-exporta el `FakeAuthRepository` de los tests unitarios para que los
/// tests "integration" no dupliquen su definición.
export '../features/auth/application/fakes.dart' show FakeAuthRepository;

/// Construye un `MaterialApp.router` con las rutas públicas reales (welcome,
/// login, register, verify-email-sent, magic-link, otp, forgot-password,
/// terms, privacy, cookies) y los notifiers reales por encima de un
/// [FakeAuthRepository]. Sin guardas de auth ni dependencias de Supabase: el
/// flujo "registro" se completa porque el fake devuelve éxitos controlados.
///
/// Para acceder a la zona privada (/home etc.) habría que añadir
/// dependencias reales de Supabase; intencionalmente las dejamos fuera para
/// que estos tests sean rápidos y deterministas.
Future<Widget> buildAppForIntegration({
  required FakeAuthRepository repo,
  List<Override> extraOverrides = const [],
  String initialLocation = '/',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  Widget emptyScaffold(BuildContext _, GoRouterState __) => const Scaffold();

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        name: 'welcome',
        builder: (_, __) => const WelcomePage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (_, __) => const RegisterPage(),
      ),
      GoRoute(
        path: '/verify-email-sent',
        name: 'verify_email_sent',
        builder: (_, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return VerifyEmailSentPage(email: email);
        },
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot_password',
        builder: (_, __) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/magic-link',
        name: 'magic_link',
        builder: (_, __) => const MagicLinkPage(),
      ),
      GoRoute(
        path: '/otp',
        name: 'otp_request',
        builder: (_, __) => const OtpRequestPage(),
      ),
      GoRoute(path: '/home', name: 'home', builder: emptyScaffold),
      GoRoute(
        path: '/terms',
        name: 'terms',
        builder: (_, __) => const TermsPage(),
      ),
      GoRoute(
        path: '/privacy',
        name: 'privacy',
        builder: (_, __) => const PrivacyPage(),
      ),
      GoRoute(
        path: '/cookies',
        name: 'cookies',
        builder: (_, __) => const CookiesPage(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(repo),
      auditLoggerProvider.overrideWithValue(const AuditLogger.noop()),
      ...extraOverrides,
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: AppLocales.all,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    ),
  );
}

/// Surface grande y pump de microtasks para que cualquier `_load()` de
/// notifiers termine antes de inspeccionar la UI. La altura (1500) es
/// suficiente para que las cards de Login (1000px reservados) y Register
/// (980px reservados) quepan completas sin scroll.
Future<void> primeApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pump();
  await tester.pump();
}
