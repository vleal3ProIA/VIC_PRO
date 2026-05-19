import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/change_email_notifier.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

import 'fakes.dart';

void main() {
  late FakeAuthRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeAuthRepository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        ...commonNotifierOverrides,
      ],
    );
    addTearDown(container.dispose);
  });

  ChangeEmailNotifier notifier() =>
      container.read(changeEmailNotifierProvider.notifier);
  ChangeEmailState state() => container.read(changeEmailNotifierProvider);

  test('initial state invalid', () {
    expect(state().status, ChangeEmailStatus.initial);
    expect(state().isValid, isFalse);
  });

  test('submit with empty email activates showErrors, no repo call',
      () async {
    await notifier().submit();
    expect(state().showErrors, isTrue);
    expect(repo.lastChangeEmail, isNull);
  });

  test('submit with invalid email does not call repo', () async {
    notifier().emailChanged('not-an-email');
    await notifier().submit();
    expect(state().status, ChangeEmailStatus.initial);
    expect(repo.lastChangeEmail, isNull);
  });

  test('submit with valid email calls repo + success with sentToEmail',
      () async {
    notifier().emailChanged('new@example.com');
    await notifier().submit();
    expect(repo.lastChangeEmail, 'new@example.com');
    expect(state().status, ChangeEmailStatus.success);
    expect(state().sentToEmail, 'new@example.com');
  });

  test('email is trimmed before reaching the repo', () async {
    notifier().emailChanged('  new@example.com  ');
    await notifier().submit();
    expect(repo.lastChangeEmail, 'new@example.com');
  });

  test('backend failure surfaces the failure', () async {
    repo.changeEmailResult = const Left(AuthUserAlreadyExists());
    notifier().emailChanged('taken@example.com');
    await notifier().submit();
    expect(state().status, ChangeEmailStatus.failure);
    expect(state().failure, isA<AuthUserAlreadyExists>());
  });

  // El form llama a `validateForm()` para decidir si abrir el dialog
  // de re-auth. Estos tests aseguran que el helper se comporta como
  // se espera sin disparar el side effect de llamar a la API.
  test('validateForm returns false on empty form and marks showErrors',
      () async {
    final ok = notifier().validateForm();
    expect(ok, isFalse);
    expect(state().showErrors, isTrue);
    expect(repo.lastChangeEmail, isNull); // NO llamada a la repo
  });

  test('validateForm returns false on malformed email', () async {
    notifier().emailChanged('not-an-email');
    final ok = notifier().validateForm();
    expect(ok, isFalse);
    expect(state().showErrors, isTrue);
    expect(repo.lastChangeEmail, isNull);
  });

  test('validateForm returns true on valid email and clears prev failure',
      () async {
    // Stage previo: un fallo anterior.
    repo.changeEmailResult = const Left(AuthUserAlreadyExists());
    notifier().emailChanged('taken@example.com');
    await notifier().submit();
    expect(state().failure, isA<AuthUserAlreadyExists>());

    // Ahora el user corrige + valida. La validacion limpia failure.
    notifier().emailChanged('fresh@example.com');
    final ok = notifier().validateForm();
    expect(ok, isTrue);
    expect(state().failure, isNull);
    expect(repo.lastChangeEmail, 'taken@example.com'); // sigue siendo el
    // anterior porque validateForm NO llama a la repo.
  });
}
