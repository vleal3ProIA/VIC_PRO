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
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
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
}
