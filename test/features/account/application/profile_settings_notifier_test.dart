import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/application/profile_settings_notifier.dart';
import 'package:myapp/features/account/domain/entities/profile.dart';
import 'package:myapp/features/account/domain/failures/profile_failure.dart';
import 'package:myapp/features/account/domain/repositories/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake controlable del ProfileRepository.
class FakeProfileRepository implements ProfileRepository {
  Either<ProfileFailure, Profile> getResult = const Right(
    Profile(id: 'u1', locale: 'en', themeMode: 'system', username: 'john'),
  );
  Either<ProfileFailure, Profile> updateResult = const Right(
    Profile(id: 'u1', locale: 'en', themeMode: 'system', username: 'john'),
  );

  String? lastDisplayName;
  String? lastLocale;
  String? lastThemeMode;
  int updateCalls = 0;

  @override
  Future<Either<ProfileFailure, Profile>> getMyProfile() async => getResult;

  @override
  Future<Either<ProfileFailure, Profile>> updateMyProfile({
    String? displayName,
    String? locale,
    String? themeMode,
  }) async {
    updateCalls++;
    lastDisplayName = displayName;
    lastLocale = locale;
    lastThemeMode = themeMode;
    return updateResult;
  }
}

void main() {
  late FakeProfileRepository repo;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = FakeProfileRepository();
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
  });

  ProfileSettingsNotifier notifier() =>
      container.read(profileSettingsNotifierProvider.notifier);
  ProfileSettingsState state() =>
      container.read(profileSettingsNotifierProvider);

  Future<void> waitLoad() async {
    notifier(); // triggers build → _load()
    await Future.microtask(() {});
    await Future.microtask(() {});
  }

  test('loads profile on build → status ready', () async {
    await waitLoad();
    expect(state().status, ProfileSettingsStatus.ready);
    expect(state().profile?.username, 'john');
  });

  test('load failure → status failure with the failure set', () async {
    repo.getResult = const Left(ProfileNotFound());
    await waitLoad();
    expect(state().status, ProfileSettingsStatus.failure);
    expect(state().failure, isA<ProfileNotFound>());
  });

  test('saveDisplayName calls repo with the trimmed name', () async {
    await waitLoad();
    await notifier().saveDisplayName('  New Name  ');
    expect(repo.lastDisplayName, 'New Name');
    expect(state().status, ProfileSettingsStatus.ready);
  });

  test('successful save increments savedTick', () async {
    await waitLoad();
    final before = state().savedTick;
    await notifier().saveDisplayName('Name');
    expect(state().savedTick, before + 1);
  });

  test('changeLocale persists languageCode to repo', () async {
    await waitLoad();
    await notifier().changeLocale(const Locale('es'));
    expect(repo.lastLocale, 'es');
  });

  test('changeThemeMode persists theme name to repo', () async {
    await waitLoad();
    await notifier().changeThemeMode(ThemeMode.dark);
    expect(repo.lastThemeMode, 'dark');
  });

  test('update failure surfaces the failure without losing the profile',
      () async {
    await waitLoad();
    repo.updateResult = const Left(ProfileUsernameTaken());
    await notifier().saveDisplayName('whatever');
    expect(state().failure, isA<ProfileUsernameTaken>());
    expect(state().profile, isNotNull);
    expect(state().status, ProfileSettingsStatus.ready);
  });
}
