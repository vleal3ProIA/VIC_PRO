import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/password_update_notifier.dart';
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

  PasswordUpdateNotifier notifier() =>
      container.read(passwordUpdateNotifierProvider.notifier);
  PasswordUpdateState state() =>
      container.read(passwordUpdateNotifierProvider);

  test('weak password keeps invalid + does not call repo', () async {
    notifier()
      ..passwordChanged('weak')
      ..confirmationChanged('weak');
    await notifier().submit();
    expect(state().status, PasswordUpdateStatus.initial);
    expect(repo.lastUpdatedPassword, isNull);
    expect(state().isValid, isFalse);
  });

  test('mismatched confirmation keeps invalid', () async {
    notifier()
      ..passwordChanged('Aa1!aaaa')
      ..confirmationChanged('Other!1Bb');
    await notifier().submit();
    expect(state().status, PasswordUpdateStatus.initial);
    expect(repo.lastUpdatedPassword, isNull);
  });

  test('valid form calls repo + success state', () async {
    notifier()
      ..passwordChanged('Aa1!aaaa')
      ..confirmationChanged('Aa1!aaaa');
    await notifier().submit();
    expect(repo.lastUpdatedPassword, 'Aa1!aaaa');
    expect(state().status, PasswordUpdateStatus.success);
  });

  test('backend failure surfaces AuthWeakPassword', () async {
    repo.updatePasswordResult = const Left(AuthWeakPassword());
    notifier()
      ..passwordChanged('Aa1!aaaa')
      ..confirmationChanged('Aa1!aaaa');
    await notifier().submit();
    expect(state().status, PasswordUpdateStatus.failure);
    expect(state().failure, isA<AuthWeakPassword>());
  });
}
