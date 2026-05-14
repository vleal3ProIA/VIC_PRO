import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/oauth_notifier.dart';
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

  OAuthNotifier notifier() => container.read(oauthNotifierProvider.notifier);
  OAuthState state() => container.read(oauthNotifierProvider);

  test('initial state is idle, no provider, no failure', () {
    expect(state().status, OAuthStatus.idle);
    expect(state().provider, isNull);
    expect(state().failure, isNull);
    expect(state().isBusy, isFalse);
  });

  test('signIn(google) OK → redirecting with provider=google', () async {
    await notifier().signIn(SocialProvider.google);
    expect(state().status, OAuthStatus.redirecting);
    expect(state().provider, SocialProvider.google);
    expect(state().isBusyWith(SocialProvider.google), isTrue);
    expect(state().isBusyWith(SocialProvider.apple), isFalse);
    expect(state().failure, isNull);
    expect(repo.signInWithGoogleCalls, 1);
  });

  test('signIn(apple) OK → redirecting with provider=apple', () async {
    await notifier().signIn(SocialProvider.apple);
    expect(state().status, OAuthStatus.redirecting);
    expect(state().provider, SocialProvider.apple);
    expect(state().isBusyWith(SocialProvider.apple), isTrue);
    expect(repo.signInWithAppleCalls, 1);
  });

  test('signIn(google) failure → status=failure with failure set', () async {
    repo.signInWithGoogleResult = const Left(AuthNetworkError());
    await notifier().signIn(SocialProvider.google);
    expect(state().status, OAuthStatus.failure);
    expect(state().failure, isA<AuthNetworkError>());
  });

  test('signIn(apple) failure → status=failure with failure set', () async {
    repo.signInWithAppleResult = const Left(AuthNetworkError());
    await notifier().signIn(SocialProvider.apple);
    expect(state().status, OAuthStatus.failure);
    expect(state().failure, isA<AuthNetworkError>());
  });

  test('signIn is a no-op while already redirecting', () async {
    await notifier().signIn(SocialProvider.google);
    expect(repo.signInWithGoogleCalls, 1);
    // Segunda llamada (incluso a otro proveedor) mientras isBusy → ignorada.
    await notifier().signIn(SocialProvider.apple);
    expect(repo.signInWithAppleCalls, 0);
  });

  test('convenience methods delegate to signIn', () async {
    await notifier().signInWithApple();
    expect(repo.signInWithAppleCalls, 1);
    expect(state().provider, SocialProvider.apple);
  });

  test('reset returns to idle', () async {
    repo.signInWithGoogleResult = const Left(AuthNetworkError());
    await notifier().signIn(SocialProvider.google);
    expect(state().status, OAuthStatus.failure);
    notifier().reset();
    expect(state().status, OAuthStatus.idle);
    expect(state().provider, isNull);
    expect(state().failure, isNull);
  });
}
