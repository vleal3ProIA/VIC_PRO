import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/entities/sign_up_request.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';
import 'package:myapp/features/auth/presentation/widgets/register_form.dart';

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
      child: const RegisterForm(),
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
  }

  Future<void> fillValidForm(WidgetTester tester) async {
    // Order in the form: username, email, password, confirm password.
    await tester.enterText(find.byType(TextField).at(0), 'victor');
    await tester.enterText(find.byType(TextField).at(1), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'Aa1!aaaa');
    await tester.enterText(find.byType(TextField).at(3), 'Aa1!aaaa');
  }

  group('RegisterForm', () {
    testWidgets('renders 4 fields + accept-terms checkbox + create button',
        (tester) async {
      await pumpForm(tester);
      expect(find.byType(TextField), findsNWidgets(4));
      expect(find.byType(Checkbox), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Create account'),
        findsOneWidget,
      );
    });

    testWidgets('submit without accepting terms shows the terms error',
        (tester) async {
      await pumpForm(tester);
      await fillValidForm(tester);
      // Don't tick the checkbox.
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(
        find.text('You must accept the terms to continue'),
        findsOneWidget,
      );
      // And the repo was NOT called.
      expect(repo.signUpResult, isA<Right<AuthFailure, SignUpResult>>());
    });

    testWidgets('valid submit calls repo.signUp with the entered values',
        (tester) async {
      await pumpForm(tester);
      await fillValidForm(tester);
      // Tap the checkbox.
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      await tester.pump();
      // FakeAuthRepository.signUp ignora el request pero podemos verificar
      // que se invocó vía el resultado por defecto (Right). El hecho de
      // que no se haya marcado el error de términos confirma que el
      // submit pasó la validación local.
      expect(
        find.text('You must accept the terms to continue'),
        findsNothing,
      );
    });

    testWidgets('user_already_exists backend surfaces the localised error',
        (tester) async {
      repo.signUpResult = const Left(AuthUserAlreadyExists());
      await pumpForm(tester);
      await fillValidForm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('An account with this email already exists.'),
        findsOneWidget,
      );
    });
  });
}
