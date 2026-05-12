import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/password_reset_notifier.dart';
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

  PasswordResetRequestNotifier notifier() =>
      container.read(passwordResetRequestNotifierProvider.notifier);
  PasswordResetRequestState state() =>
      container.read(passwordResetRequestNotifierProvider);

  test('empty email keeps initial status + activates showErrors on submit',
      () async {
    await notifier().submit();
    expect(state().status, PasswordResetRequestStatus.initial);
    expect(state().showErrors, isTrue);
    expect(repo.lastResetEmail, isNull);
  });

  test('valid email triggers repo + success state with sentToEmail', () async {
    notifier().emailChanged('jane@example.com');
    await notifier().submit();
    expect(repo.lastResetEmail, 'jane@example.com');
    expect(state().status, PasswordResetRequestStatus.success);
    expect(state().sentToEmail, 'jane@example.com');
  });

  test('rate limited backend surfaces AuthRateLimited', () async {
    repo.sendPasswordResetResult = const Left(AuthRateLimited());
    notifier().emailChanged('jane@example.com');
    await notifier().submit();
    expect(state().status, PasswordResetRequestStatus.failure);
    expect(state().failure, isA<AuthRateLimited>());
  });
}
