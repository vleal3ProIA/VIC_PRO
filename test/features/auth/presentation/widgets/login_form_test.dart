import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';
import 'package:myapp/features/auth/presentation/widgets/login_form.dart';

import '../../../../helpers/pump_widget.dart';
import '../../application/fakes.dart';

void main() {
  late FakeAuthRepository repo;

  setUp(() {
    repo = FakeAuthRepository();
  });

  Future<void> pumpForm(WidgetTester tester) async {
    await pumpForTest(
      tester,
      child: const LoginForm(),
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
  }

  group('LoginForm', () {
    testWidgets('renders email + password fields and sign-in button',
        (tester) async {
      await pumpForm(tester);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    });

    testWidgets('submitting empty form shows the required error', (tester) async {
      await pumpForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      // El error se renderiza bajo el AppTextField del campo password.
      expect(find.text('This field is required'), findsWidgets);
      // Y NO se llama al repo.
      expect(repo.lastSignInEmail, isNull);
    });

    testWidgets('invalid email shows the email validation error',
        (tester) async {
      await pumpForm(tester);
      await tester.enterText(find.byType(TextField).first, 'not-an-email');
      await tester.pump();
      expect(find.text('Invalid email address'), findsOneWidget);
    });

    testWidgets('valid submit calls signIn with the entered credentials',
        (tester) async {
      await pumpForm(tester);
      await tester.enterText(find.byType(TextField).first, 'me@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'pa55word');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump(); // setState submitting
      await tester.pump(); // settle future
      expect(repo.lastSignInEmail, 'me@example.com');
      expect(repo.lastSignInPassword, 'pa55word');
    });

    testWidgets('invalid credentials backend surfaces the localised error',
        (tester) async {
      repo.signInResult = const Left(AuthInvalidCredentials());
      await pumpForm(tester);
      await tester.enterText(find.byType(TextField).first, 'me@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Invalid email or password.'), findsOneWidget);
    });
  });
}
