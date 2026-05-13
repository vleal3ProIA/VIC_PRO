import 'package:flutter_dotenv/flutter_dotenv.dart';
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

  setUpAll(() {
    // El notifier lee EnvConfig.otpCodeLength desde dotenv. En tests no
    // cargamos el .env real; vacío + fallback="6" basta para validar la
    // lógica del notifier sin tocar IO.
    dotenv.testLoad(fileInput: 'OTP_CODE_LENGTH=6');
  });

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

  test('initial state holds the email + codeLength=6 + invalid', () {
    expect(state().email, email);
    expect(state().codeLength, 6);
    expect(state().code, '');
    expect(state().isValid, isFalse);
  });

  test('submit with <codeLength digits does NOT call repo', () async {
    notifier().codeChanged('1234');
    await notifier().submit();
    expect(state().status, OtpVerifyStatus.initial);
    expect(repo.lastOtpVerifyToken, isNull);
  });

  test('submit with full-length code calls repo and emits success', () async {
    notifier().codeChanged('123456');
    await notifier().submit();
    expect(repo.lastOtpVerifyEmail, email);
    expect(repo.lastOtpVerifyToken, '123456');
    expect(state().status, OtpVerifyStatus.success);
  });

  test('invalid code from backend surfaces AuthOtpInvalid', () async {
    repo.verifyOtpResult = const Left(AuthOtpInvalid());
    notifier().codeChanged('000000');
    await notifier().submit();
    expect(state().status, OtpVerifyStatus.failure);
    expect(state().failure, isA<AuthOtpInvalid>());
  });

  test('typing again after failure clears the previous failure', () async {
    repo.verifyOtpResult = const Left(AuthOtpInvalid());
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

  group('codeLength=8', () {
    setUpAll(() {
      dotenv.testLoad(fileInput: 'OTP_CODE_LENGTH=8');
    });

    test('isValid requires exactly 8 digits', () {
      // Force re-build with new env.
      container.invalidate(otpVerifyNotifierProvider(email));
      final n = container.read(otpVerifyNotifierProvider(email).notifier);
      expect(container.read(otpVerifyNotifierProvider(email)).codeLength, 8);

      n.codeChanged('1234567');
      expect(container.read(otpVerifyNotifierProvider(email)).isValid, isFalse);
      n.codeChanged('12345678');
      expect(container.read(otpVerifyNotifierProvider(email)).isValid, isTrue);
    });
  });
}
