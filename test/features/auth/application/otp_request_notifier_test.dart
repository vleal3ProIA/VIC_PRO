import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/otp_request_notifier.dart';
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

  OtpRequestNotifier notifier() =>
      container.read(otpRequestNotifierProvider.notifier);
  OtpRequestState state() => container.read(otpRequestNotifierProvider);

  test('initial state is invalid', () {
    expect(state().status, OtpRequestStatus.initial);
    expect(state().isValid, isFalse);
  });

  test('submit with empty email activates showErrors and does NOT call repo',
      () async {
    await notifier().submit();
    expect(state().showErrors, isTrue);
    expect(state().status, OtpRequestStatus.initial);
    expect(repo.lastOtpRequestEmail, isNull);
  });

  test('submit with valid email calls repo and emits success', () async {
    notifier().emailChanged('jane@example.com');
    await notifier().submit();
    expect(repo.lastOtpRequestEmail, 'jane@example.com');
    expect(state().status, OtpRequestStatus.success);
    expect(state().sentToEmail, 'jane@example.com');
  });

  test('rate-limited backend surfaces AuthRateLimited', () async {
    repo.requestOtpResult = const Left(AuthRateLimited());
    notifier().emailChanged('jane@example.com');
    await notifier().submit();
    expect(state().status, OtpRequestStatus.failure);
    expect(state().failure, isA<AuthRateLimited>());
  });
}
