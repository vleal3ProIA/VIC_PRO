import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/change_password_notifier.dart';
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
        auditLoggerNoopOverride,
      ],
    );
    addTearDown(container.dispose);
  });

  ChangePasswordNotifier notifier() =>
      container.read(changePasswordNotifierProvider.notifier);
  ChangePasswordState state() =>
      container.read(changePasswordNotifierProvider);

  test('initial state is invalid', () {
    expect(state().status, ChangePasswordStatus.initial);
    expect(state().isValid, isFalse);
  });

  test('submit with empty form activates showErrors and does not call repo',
      () async {
    await notifier().submit();
    expect(state().showErrors, isTrue);
    expect(repo.lastChangePasswordNew, isNull);
  });

  test('submit with weak new password does not call repo', () async {
    notifier()
      ..currentPasswordChanged('whatever')
      ..newPasswordChanged('weak')
      ..confirmationChanged('weak');
    await notifier().submit();
    expect(state().status, ChangePasswordStatus.initial);
    expect(repo.lastChangePasswordNew, isNull);
  });

  test('submit with valid form calls repo and emits success', () async {
    notifier()
      ..currentPasswordChanged('OldPass1!')
      ..newPasswordChanged('NewPass1!')
      ..confirmationChanged('NewPass1!');
    await notifier().submit();
    expect(repo.lastChangePasswordCurrent, 'OldPass1!');
    expect(repo.lastChangePasswordNew, 'NewPass1!');
    expect(state().status, ChangePasswordStatus.success);
  });

  test('wrong current password surfaces AuthInvalidCredentials', () async {
    repo.changePasswordResult = const Left(AuthInvalidCredentials());
    notifier()
      ..currentPasswordChanged('Wrong1!')
      ..newPasswordChanged('NewPass1!')
      ..confirmationChanged('NewPass1!');
    await notifier().submit();
    expect(state().status, ChangePasswordStatus.failure);
    expect(state().failure, isA<AuthInvalidCredentials>());
  });

  test('mismatched confirmation does not call repo', () async {
    notifier()
      ..currentPasswordChanged('OldPass1!')
      ..newPasswordChanged('NewPass1!')
      ..confirmationChanged('Different1!');
    await notifier().submit();
    expect(repo.lastChangePasswordNew, isNull);
  });
}
