import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/mfa_setup_notifier.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
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

  MfaSetupNotifier notifier() =>
      container.read(mfaSetupNotifierProvider.notifier);
  MfaSetupState state() => container.read(mfaSetupNotifierProvider);

  /// Construye el notifier y espera a que `_init()` (async, encadenado)
  /// termine.
  Future<void> settle() async {
    notifier(); // fuerza build() → _init()
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('sin factor previo (listFactors → [])', () {
    test('init arranca enrollment → step qrCode con enrollment', () async {
      await settle();
      expect(state().step, MfaSetupStep.qrCode);
      expect(state().enrollment, isNotNull);
      expect(state().enrollment!.factorId, 'fake-factor');
    });

    test('verify con código completo → step done', () async {
      await settle();
      notifier().codeChanged('123456');
      await notifier().verify();
      expect(state().step, MfaSetupStep.done);
      expect(repo.lastVerifyMfaFactorId, 'fake-factor');
    });

    test('verify con <6 dígitos es no-op', () async {
      await settle();
      notifier().codeChanged('123');
      await notifier().verify();
      expect(state().step, MfaSetupStep.qrCode);
      expect(repo.lastVerifyMfaCode, isNull);
    });

    test('verify failure → vuelve a qrCode con failure', () async {
      await settle();
      repo.verifyMfaEnrollmentResult = const Left(AuthMfaInvalid());
      notifier().codeChanged('000000');
      await notifier().verify();
      expect(state().step, MfaSetupStep.qrCode);
      expect(state().failure, isA<AuthMfaInvalid>());
    });
  });

  group('con factor TOTP verificado', () {
    setUp(() {
      repo.listFactorsResult = const Right([
        MfaFactor(id: 'f1', type: 'totp', status: 'verified'),
      ]);
    });

    test('init → step alreadyEnabled con existingFactorId', () async {
      await settle();
      expect(state().step, MfaSetupStep.alreadyEnabled);
      expect(state().existingFactorId, 'f1');
    });

    test('disable OK → step disabled', () async {
      await settle();
      await notifier().disable();
      expect(state().step, MfaSetupStep.disabled);
    });

    test('disable failure → vuelve a alreadyEnabled con failure', () async {
      await settle();
      repo.unenrollMfaResult = const Left(AuthUnknown());
      await notifier().disable();
      expect(state().step, MfaSetupStep.alreadyEnabled);
      expect(state().failure, isA<AuthUnknown>());
    });
  });

  test('un factor unverified NO cuenta como enabled → arranca enrollment',
      () async {
    repo.listFactorsResult = const Right([
      MfaFactor(id: 'f1', type: 'totp', status: 'unverified'),
    ]);
    await settle();
    expect(state().step, MfaSetupStep.qrCode);
  });
}
