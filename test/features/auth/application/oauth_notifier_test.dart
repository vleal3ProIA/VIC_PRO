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

  test('initial state is idle, no failure', () {
    expect(state().status, OAuthStatus.idle);
    expect(state().failure, isNull);
    expect(state().isBusy, isFalse);
  });

  test('signInWithGoogle OK → stays redirecting (browser navigates away)',
      () async {
    await notifier().signInWithGoogle();
    expect(state().status, OAuthStatus.redirecting);
    expect(state().failure, isNull);
    expect(repo.signInWithGoogleCalls, 1);
  });

  test('signInWithGoogle failure → status=failure with failure set', () async {
    repo.signInWithGoogleResult = const Left(AuthNetworkError());
    await notifier().signInWithGoogle();
    expect(state().status, OAuthStatus.failure);
    expect(state().failure, isA<AuthNetworkError>());
  });

  test('signInWithGoogle is a no-op while already redirecting', () async {
    await notifier().signInWithGoogle();
    expect(repo.signInWithGoogleCalls, 1);
    // Segunda llamada mientras isBusy → no vuelve a llamar al repo.
    await notifier().signInWithGoogle();
    expect(repo.signInWithGoogleCalls, 1);
  });

  test('reset returns to idle', () async {
    repo.signInWithGoogleResult = const Left(AuthNetworkError());
    await notifier().signInWithGoogle();
    expect(state().status, OAuthStatus.failure);
    notifier().reset();
    expect(state().status, OAuthStatus.idle);
    expect(state().failure, isNull);
  });
}
