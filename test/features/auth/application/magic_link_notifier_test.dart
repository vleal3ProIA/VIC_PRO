import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/magic_link_notifier.dart';
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

  MagicLinkNotifier notifier() =>
      container.read(magicLinkNotifierProvider.notifier);
  MagicLinkState state() => container.read(magicLinkNotifierProvider);

  test('initial state is invalid + not submitting + no showErrors', () {
    expect(state().status, MagicLinkStatus.initial);
    expect(state().isValid, isFalse);
    expect(state().showErrors, isFalse);
  });

  test('submit with empty email activates showErrors and does NOT call repo',
      () async {
    await notifier().submit();
    expect(state().showErrors, isTrue);
    expect(state().status, MagicLinkStatus.initial);
    expect(repo.lastMagicLinkEmail, isNull);
  });

  test('submit with invalid email keeps initial + does NOT call repo',
      () async {
    notifier().emailChanged('not-an-email');
    await notifier().submit();
    expect(state().status, MagicLinkStatus.initial);
    expect(repo.lastMagicLinkEmail, isNull);
  });

  test('submit with valid email calls repo and emits success', () async {
    notifier().emailChanged('jane@example.com');
    await notifier().submit();
    expect(repo.lastMagicLinkEmail, 'jane@example.com');
    expect(state().status, MagicLinkStatus.success);
    expect(state().sentToEmail, 'jane@example.com');
    expect(state().failure, isNull);
  });

  test('email is trimmed before reaching the repo', () async {
    notifier().emailChanged('  jane@example.com  ');
    await notifier().submit();
    expect(repo.lastMagicLinkEmail, 'jane@example.com');
  });

  test('rate-limited backend surfaces AuthRateLimited', () async {
    repo.magicLinkResult = const Left(AuthRateLimited());
    notifier().emailChanged('jane@example.com');
    await notifier().submit();
    expect(state().status, MagicLinkStatus.failure);
    expect(state().failure, isA<AuthRateLimited>());
  });

  test('typing again after failure clears the previous failure', () async {
    repo.magicLinkResult = const Left(AuthRateLimited());
    notifier().emailChanged('jane@example.com');
    await notifier().submit();
    expect(state().failure, isNotNull);

    notifier().emailChanged('other@example.com');
    expect(state().failure, isNull);
  });
}
