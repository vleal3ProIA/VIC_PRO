import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/mfa_challenge_notifier.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

import 'fakes.dart';

void main() {
  late FakeAuthRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeAuthRepository();
    repo.listFactorsResult = const Right([
      MfaFactor(
        id: 'factor-1',
        type: 'totp',
        status: 'verified',
        friendlyName: 'myapp',
      ),
    ]);
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        ...commonNotifierOverrides,
      ],
    );
    addTearDown(container.dispose);
  });

  MfaChallengeNotifier notifier() =>
      container.read(mfaChallengeNotifierProvider.notifier);
  MfaChallengeState state() => container.read(mfaChallengeNotifierProvider);

  test('on build, loads the first verified TOTP factor', () async {
    notifier(); // forces build
    // wait microtask to let _loadFactor complete
    await Future.microtask(() {});
    await Future.microtask(() {});
    expect(state().status, MfaChallengeStatus.ready);
    expect(state().factor?.id, 'factor-1');
  });

  test('verify with valid code calls repo and emits success', () async {
    notifier();
    await Future.microtask(() {});
    await Future.microtask(() {});

    notifier().codeChanged('123456');
    await notifier().verify();
    expect(state().status, MfaChallengeStatus.success);
    expect(repo.lastChallengeMfaFactorId, 'factor-1');
    expect(repo.lastChallengeMfaCode, '123456');
  });

  test('verify with <6 digits is no-op', () async {
    notifier();
    await Future.microtask(() {});
    await Future.microtask(() {});

    notifier().codeChanged('123');
    await notifier().verify();
    expect(state().status, MfaChallengeStatus.ready);
    expect(repo.lastChallengeMfaCode, isNull);
  });

  test('AuthMfaInvalid backend → status=failure', () async {
    notifier();
    await Future.microtask(() {});
    await Future.microtask(() {});

    repo.challengeMfaResult = const Left(AuthMfaInvalid());
    notifier().codeChanged('000000');
    await notifier().verify();
    expect(state().status, MfaChallengeStatus.failure);
    expect(state().failure, isA<AuthMfaInvalid>());
  });

  test('typing again after failure clears the failure', () async {
    notifier();
    await Future.microtask(() {});
    await Future.microtask(() {});

    repo.challengeMfaResult = const Left(AuthMfaInvalid());
    notifier().codeChanged('000000');
    await notifier().verify();
    expect(state().failure, isNotNull);
    notifier().codeChanged('111111');
    expect(state().failure, isNull);
  });

  // ----- Códigos de recuperación -----

  test('toggleRecoveryMode cambia al modo de código de recuperación', () async {
    notifier();
    await Future.microtask(() {});
    await Future.microtask(() {});

    expect(state().useRecoveryCode, isFalse);
    notifier().toggleRecoveryMode();
    expect(state().useRecoveryCode, isTrue);
  });

  test('verify en modo recovery llama a repo.verifyRecoveryCode', () async {
    notifier();
    await Future.microtask(() {});
    await Future.microtask(() {});

    notifier().toggleRecoveryMode();
    notifier().recoveryCodeChanged('aaaaa-11111');
    await notifier().verify();
    expect(repo.lastRecoveryCodeVerified, 'aaaaa-11111');
    expect(state().status, MfaChallengeStatus.success);
  });

  test('verify en modo recovery con código vacío es no-op', () async {
    notifier();
    await Future.microtask(() {});
    await Future.microtask(() {});

    notifier().toggleRecoveryMode();
    await notifier().verify();
    expect(repo.lastRecoveryCodeVerified, isNull);
    expect(state().status, MfaChallengeStatus.ready);
  });

  test('código de recuperación inválido → status=failure', () async {
    notifier();
    await Future.microtask(() {});
    await Future.microtask(() {});

    repo.verifyRecoveryCodeResult = const Left(AuthMfaInvalid());
    notifier().toggleRecoveryMode();
    notifier().recoveryCodeChanged('codigo-malo');
    await notifier().verify();
    expect(state().status, MfaChallengeStatus.failure);
    expect(state().failure, isA<AuthMfaInvalid>());
  });
}
