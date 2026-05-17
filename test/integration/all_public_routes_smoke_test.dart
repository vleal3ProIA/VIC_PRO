import 'package:flutter_test/flutter_test.dart';
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

import '_helpers.dart';

/// Smoke test "no se rompe nada al renderizar":
/// arranca la app en cada ruta pública y verifica que la página
/// correspondiente está en el árbol sin lanzar excepciones.
///
/// Pillará regresiones donde un cambio en providers, theme, locale o
/// dependencias rompe una pantalla aunque otras sigan funcionando.
/// Más barato que un test E2E real que navega, pero detecta el 80% de
/// los problemas: import faltante, provider no overriddeado, widget
/// con assertion failure al construir.
void main() {
  for (final route in _publicRoutes) {
    testWidgets('renders ${route.path} without errors', (tester) async {
      final repo = FakeAuthRepository();
      final app = await buildAppForIntegration(
        repo: repo,
        initialLocation: route.path,
      );

      await tester.pumpWidget(app);
      await primeApp(tester);

      // El widget esperado está en pantalla — si la build hubiese
      // lanzado, finder devuelve cero y falla aquí con contexto claro.
      expect(
        find.byType(route.pageType),
        findsOneWidget,
        reason: 'Ruta ${route.path} no renderiza ${route.pageType}',
      );

      // No hay excepciones pendientes acumuladas durante el frame.
      expect(tester.takeException(), isNull);
    });
  }
}

/// Una entrada del tabla de rutas públicas a testear. Sincronizar a
/// mano si añadimos nuevas rutas públicas — el `_helpers.dart` define
/// el subset cubierto por la infra de tests.
class _RouteEntry {
  const _RouteEntry(this.path, this.pageType);
  final String path;
  final Type pageType;
}

const _publicRoutes = <_RouteEntry>[
  _RouteEntry('/', WelcomePage),
  _RouteEntry('/login', LoginPage),
  _RouteEntry('/register', RegisterPage),
  _RouteEntry('/forgot-password', ForgotPasswordPage),
  _RouteEntry('/magic-link', MagicLinkPage),
  _RouteEntry('/otp', OtpRequestPage),
  _RouteEntry('/verify-email-sent', VerifyEmailSentPage),
  _RouteEntry('/terms', TermsPage),
  _RouteEntry('/privacy', PrivacyPage),
  _RouteEntry('/cookies', CookiesPage),
];
