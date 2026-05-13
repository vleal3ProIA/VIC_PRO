import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/mfa_setup_notifier.dart';
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

  test('initial state is idle, no enrollment, no code', () {
    expect(state().step, MfaSetupStep.idle);
    expect(state().enrollment, isNull);
    expect(state().code, isEmpty);
  });

  test('startEnrollment OK → step=qrCode with enrollment payload', () async {
    await notifier().startEnrollment(friendlyName: 'myapp');
    expect(state().step, MfaSetupStep.qrCode);
    expect(state().enrollment, isNotNull);
    expect(state().enrollment!.factorId, 'fake-factor');
  });

  test('verify with full code OK → step=done', () async {
    await notifier().startEnrollment();
    notifier().codeChanged('123456');
    await notifier().verify();
    expect(state().step, MfaSetupStep.done);
    expect(repo.lastVerifyMfaFactorId, 'fake-factor');
    expect(repo.lastVerifyMfaCode, '123456');
  });

  test('verify with <6 digits is a no-op', () async {
    await notifier().startEnrollment();
    notifier().codeChanged('123');
    await notifier().verify();
    expect(state().step, MfaSetupStep.qrCode);
    expect(repo.lastVerifyMfaCode, isNull);
  });

  test('verify failure → returns to qrCode with failure set', () async {
    await notifier().startEnrollment();
    repo.verifyMfaEnrollmentResult = const Left(AuthMfaInvalid());
    notifier().codeChanged('000000');
    await notifier().verify();
    expect(state().step, MfaSetupStep.qrCode);
    expect(state().failure, isA<AuthMfaInvalid>());
  });
}
