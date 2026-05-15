import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/login_notifier.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  late FakeAuthRepository repo;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = FakeAuthRepository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...commonNotifierOverrides,
      ],
    );
    addTearDown(container.dispose);
  });

  LoginNotifier notifier() => container.read(loginNotifierProvider.notifier);
  LoginState state() => container.read(loginNotifierProvider);

  test('initial state is invalid + not submitting + no showErrors + no remember',
      () {
    expect(state().status, LoginStatus.initial);
    expect(state().isValid, isFalse);
    expect(state().showErrors, isFalse);
    expect(state().rememberMe, isFalse);
  });

  test('submit with empty form turns on showErrors and does not call repo',
      () async {
    await notifier().submit();
    expect(state().showErrors, isTrue);
    expect(state().status, LoginStatus.initial);
    expect(repo.lastSignInEmail, isNull);
  });

  test('submit with valid form calls repo and emits success', () async {
    notifier()
      ..emailChanged('john@example.com')
      ..passwordChanged('whatever');
    await notifier().submit();
    expect(repo.lastSignInEmail, 'john@example.com');
    expect(repo.lastSignInPassword, 'whatever');
    expect(state().status, LoginStatus.success);
    expect(state().failure, isNull);
  });

  test('submit with invalid credentials surfaces AuthInvalidCredentials',
      () async {
    repo.signInResult = const Left(AuthInvalidCredentials());
    notifier()
      ..emailChanged('john@example.com')
      ..passwordChanged('wrong');
    await notifier().submit();
    expect(state().status, LoginStatus.failure);
    expect(state().failure, isA<AuthInvalidCredentials>());
  });

  test('changing email after failure clears the failure', () async {
    repo.signInResult = const Left(AuthInvalidCredentials());
    notifier()
      ..emailChanged('john@example.com')
      ..passwordChanged('x');
    await notifier().submit();
    expect(state().failure, isNotNull);
    notifier().emailChanged('jane@example.com');
    expect(state().failure, isNull);
  });

  group('rememberMe', () {
    test('default is false', () {
      expect(state().rememberMe, isFalse);
    });

    test('toggle via rememberMeChanged', () {
      notifier().rememberMeChanged(value: true);
      expect(state().rememberMe, isTrue);
      notifier().rememberMeChanged(value: false);
      expect(state().rememberMe, isFalse);
    });

    test('submit persists rememberMe=true to SharedPreferences', () async {
      notifier()
        ..emailChanged('john@example.com')
        ..passwordChanged('whatever')
        ..rememberMeChanged(value: true);
      await notifier().submit();
      expect(prefs.getBool('auth_remember_me'), isTrue);
    });

    test('submit persists rememberMe=false to SharedPreferences', () async {
      notifier()
        ..emailChanged('john@example.com')
        ..passwordChanged('whatever');
      // rememberMe stays false
      await notifier().submit();
      expect(prefs.getBool('auth_remember_me'), isFalse);
    });
  });
}
