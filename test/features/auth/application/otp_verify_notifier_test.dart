import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/otp_verify_notifier.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

import 'fakes.dart';

void main() {
  late FakeAuthRepository repo;
  late ProviderContainer container;
  const email = 'jane@example.com';

  setUp(() {
    repo = FakeAuthRepository();
    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  OtpVerifyNotifier notifier() =>
      container.read(otpVerifyNotifierProvider(email).notifier);
  OtpVerifyState state() => container.read(otpVerifyNotifierProvider(email));

  test('initial state holds the email and is invalid', () {
    expect(state().email, email);
    expect(state().code, '');
    expect(state().isValid, isFalse);
  });

  test('submit with <6 digits does NOT call repo', () async {
    notifier().codeChanged('1234');
    await notifier().submit();
    expect(state().status, OtpVerifyStatus.initial);
    expect(repo.lastOtpVerifyToken, isNull);
  });

  test('submit with valid 6-digit code calls repo and emits success',
      () async {
    notifier().codeChanged('123456');
    await notifier().submit();
    expect(repo.lastOtpVerifyEmail, email);
    expect(repo.lastOtpVerifyToken, '123456');
    expect(state().status, OtpVerifyStatus.success);
  });

  test('invalid code from backend surfaces AuthInvalidCredentials', () async {
    repo.verifyOtpResult = const Left(AuthInvalidCredentials());
    notifier().codeChanged('000000');
    await notifier().submit();
    expect(state().status, OtpVerifyStatus.failure);
    expect(state().failure, isA<AuthInvalidCredentials>());
  });

  test('typing again after failure clears the previous failure', () async {
    repo.verifyOtpResult = const Left(AuthInvalidCredentials());
    notifier().codeChanged('000000');
    await notifier().submit();
    expect(state().failure, isNotNull);

    notifier().codeChanged('111111');
    expect(state().failure, isNull);
  });

  test('family scopes state per email', () {
    container.read(otpVerifyNotifierProvider(email).notifier).codeChanged('1');
    container
        .read(otpVerifyNotifierProvider('other@example.com').notifier)
        .codeChanged('9');
    expect(container.read(otpVerifyNotifierProvider(email)).code, '1');
    expect(
      container.read(otpVerifyNotifierProvider('other@example.com')).code,
      '9',
    );
  });
}
