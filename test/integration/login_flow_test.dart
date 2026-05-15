import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/auth/presentation/pages/login_page.dart';

import '_helpers.dart';

/// End-to-end del **flujo de login** con repo fake:
///
///   /            (WelcomePage)
///   → /login     (clic en icono "Sign in" del PublicTopBar)
///   → submit del LoginForm con credenciales válidas
///   → el fake registra la llamada (no redirigimos a /home porque eso
///     dependería de Supabase y de los guards del router real).
///
/// El objetivo es validar que: navegación pública entre welcome y login
/// funciona, el LoginForm envía las credenciales al notifier y el notifier
/// invoca al repositorio con los valores correctos.
void main() {
  testWidgets(
    'welcome → login → submit → repo.signIn recibe credenciales',
    (tester) async {
      final repo = FakeAuthRepository();
      final app = await buildAppForIntegration(repo: repo);

      await tester.pumpWidget(app);
      await primeApp(tester);

      // 1) Welcome → tap "Sign in" del AppBar.
      await tester.tap(find.byIcon(Icons.login));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);

      // 2) Rellenamos email + password.
      //    En LoginForm los AppTextField son los dos primeros TextField:
      //      0 → email
      //      1 → password
      await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'Sup3rSeguro!');
      await tester.pumpAndSettle();

      // 3) Pulsamos el botón "Sign in" — el primer FilledButton del form.
      final submit = find.byType(FilledButton).first;
      await tester.tap(submit);
      await tester.pumpAndSettle();

      // 4) El fake recibió la llamada con los valores correctos.
      expect(repo.lastSignInEmail, 'user@example.com');
      expect(repo.lastSignInPassword, 'Sup3rSeguro!');
    },
  );
}
