import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/domain/entities/sign_up_request.dart';
import 'package:myapp/features/auth/presentation/pages/login_page.dart';
import 'package:myapp/features/auth/presentation/pages/register_page.dart';
import 'package:myapp/features/auth/presentation/pages/verify_email_sent_page.dart';
import 'package:myapp/features/welcome/presentation/pages/welcome_page.dart';

import '_helpers.dart';

/// End-to-end del **flujo de registro** atravesando varias pantallas reales:
///
///   /            (WelcomePage)
///   → /login     (clic en icono "Sign in" del PublicTopBar)
///   → /register  (clic en "Create one" desde LoginForm)
///   → submit del RegisterForm con el repo fake
///   → /verify-email-sent  (navegación automática tras el éxito)
///
/// El `AuthRepository` es un fake controlable: no toca Supabase. Sirve para
/// validar **integración real entre router, formularios y notifiers** sin
/// depender del backend.
void main() {
  testWidgets(
    'welcome → login → register → submit → verify-email-sent',
    (tester) async {
      final repo = FakeAuthRepository()
        // El fake devuelve el email recibido en signUp para que el notifier
        // lo propague a la pantalla de verificación. Por defecto el fake
        // devuelve un email vacío.
        ..signUpResult = const Right(
          SignUpResult(
            email: 'newuser@example.com',
            needsEmailConfirmation: true,
          ),
        );
      final app = await buildAppForIntegration(repo: repo);

      await tester.pumpWidget(app);
      await primeApp(tester);

      // 1) Estamos en WelcomePage.
      expect(find.byType(WelcomePage), findsOneWidget);

      // 2) Hay un IconButton de "Sign in" en el AppBar. Lo pulsamos.
      final signInIcon = find.byIcon(Icons.login);
      expect(signInIcon, findsOneWidget);
      await tester.tap(signInIcon);
      await tester.pumpAndSettle();

      // 3) Estamos en LoginPage. El RegisterForm tiene un TextButton para ir
      //    a /register; en LoginForm el equivalente es "Create one".
      expect(find.byType(LoginPage), findsOneWidget);

      // El link a registro lleva el texto localizado de "Create account" /
      // "Create one". Lo buscamos por el TextButton dentro de LoginForm.
      // Hay 1 solo TextButton de "create an account" en la pantalla.
      // (Hay otros TextButton — `forgot password`, `magic link`, etc. — pero
      // el de registro es el último a la derecha en la línea final.)
      final createAccountLink = find.text('Create one');
      expect(createAccountLink, findsOneWidget);
      await tester.tap(createAccountLink);
      await tester.pumpAndSettle();

      // 4) Estamos en RegisterPage.
      expect(find.byType(RegisterPage), findsOneWidget);

      // 5) Rellenamos el formulario. Los AppTextField son TextField estándar
      //    bajo el capó; los seleccionamos por su label (placeholder).
      await tester.enterText(find.byType(TextField).at(0), 'newuser');
      await tester.enterText(
        find.byType(TextField).at(1),
        'newuser@example.com',
      );
      await tester.enterText(find.byType(TextField).at(2), 'Sup3rSeguro!');
      await tester.enterText(find.byType(TextField).at(3), 'Sup3rSeguro!');

      // 6) Aceptamos términos.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // 7) Pulsamos "Create account" — el primer FilledButton dentro del form.
      final submit = find.byType(FilledButton).first;
      await tester.tap(submit);
      await tester.pumpAndSettle();

      // 8) Tras éxito, el RegisterForm navega a /verify-email-sent con
      //    queryParameter ?email=newuser@example.com.
      expect(find.byType(VerifyEmailSentPage), findsOneWidget);

      // Y el fake recibió la llamada.
      // (signUpResult devuelve el email recibido; aquí confiamos en que el
      // notifier lo propagó.)
      expect(find.textContaining('newuser@example.com'), findsWidgets);
    },
  );
}
