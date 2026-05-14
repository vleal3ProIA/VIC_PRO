import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/account_deletion_notifier.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
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

  AccountDeletionNotifier notifier() =>
      container.read(accountDeletionNotifierProvider.notifier);
  AccountDeletionState state() =>
      container.read(accountDeletionNotifierProvider);

  test('initial state: empty, not acknowledged, invalid', () {
    expect(state().password, isEmpty);
    expect(state().acknowledged, isFalse);
    expect(state().isValid, isFalse);
    expect(state().status, AccountDeletionStatus.initial);
  });

  test('isValid requires both password and acknowledgement', () {
    notifier().passwordChanged('secret123');
    expect(state().isValid, isFalse);
    notifier().acknowledgedChanged(value: true);
    expect(state().isValid, isTrue);
  });

  test('submit without password is a no-op that shows errors', () async {
    notifier().acknowledgedChanged(value: true);
    await notifier().submit();
    expect(repo.deleteAccountCalls, 0);
    expect(state().showErrors, isTrue);
    expect(state().status, AccountDeletionStatus.initial);
  });

  test('submit without acknowledgement is a no-op', () async {
    notifier().passwordChanged('secret123');
    await notifier().submit();
    expect(repo.deleteAccountCalls, 0);
  });

  test('valid submit calls repo and emits success', () async {
    notifier().passwordChanged('secret123');
    notifier().acknowledgedChanged(value: true);
    await notifier().submit();
    expect(repo.deleteAccountCalls, 1);
    expect(repo.lastDeleteAccountPassword, 'secret123');
    expect(state().status, AccountDeletionStatus.success);
  });

  test('wrong password surfaces AuthInvalidCredentials', () async {
    repo.deleteAccountResult = const Left(AuthInvalidCredentials());
    notifier().passwordChanged('wrong');
    notifier().acknowledgedChanged(value: true);
    await notifier().submit();
    expect(state().status, AccountDeletionStatus.failure);
    expect(state().failure, isA<AuthInvalidCredentials>());
  });

  test('typing again after failure clears the previous failure', () async {
    repo.deleteAccountResult = const Left(AuthNetworkError());
    notifier().passwordChanged('secret123');
    notifier().acknowledgedChanged(value: true);
    await notifier().submit();
    expect(state().failure, isA<AuthNetworkError>());

    notifier().passwordChanged('secret1234');
    expect(state().failure, isNull);
  });
}
