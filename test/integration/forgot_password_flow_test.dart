import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:myapp/features/auth/presentation/pages/login_page.dart';

import '_helpers.dart';

/// E2E del **flujo de password reset**:
///
///   /login → tap "Forgot password?" → /forgot-password
///   → rellenar email → submit → repo.sendPasswordReset recibe la llamada
///
/// Cubre el cableado del LoginPage hacia /forgot-password y el form
/// de reset hasta el repo. Como el repo es fake, no comprobamos
/// navegación a "password-reset-sent" (que requeriría el provider de
/// éxito): paramos al recibir la llamada en el fake.
void main() {
  testWidgets('login → forgot password → submit → repo recibe email',
      (tester) async {
    final repo = FakeAuthRepository();
    final app = await buildAppForIntegration(
      repo: repo,
      initialLocation: '/login',
    );

    await tester.pumpWidget(app);
    await primeApp(tester);

    expect(find.byType(LoginPage), findsOneWidget);

    // Tap "Forgot password?" — es el TextButton con el texto localizado.
    // Lo encontramos por su texto en EN (locale fijo en buildAppForIntegration).
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordPage), findsOneWidget);

    // Rellenar email — el ForgotPasswordPage tiene un único TextField.
    await tester.enterText(find.byType(TextField).first, 'reset@example.com');
    await tester.pumpAndSettle();

    // Submit — primer FilledButton.
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    // El fake recibió la llamada con el email.
    expect(repo.lastResetEmail, 'reset@example.com');
  });
}
