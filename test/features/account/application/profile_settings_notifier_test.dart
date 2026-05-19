import 'dart:typed_data';

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
  Either<ProfileFailure, Profile> uploadAvatarResult = const Right(
    Profile(
      id: 'u1',
      locale: 'en',
      themeMode: 'system',
      username: 'john',
      avatarUrl: 'https://example.com/a.png?v=1',
    ),
  );

  String? lastDisplayName;
  String? lastLocale;
  String? lastThemeMode;
  String? lastAvatarUrl;
  int updateCalls = 0;
  int uploadAvatarCalls = 0;
  String? lastAvatarContentType;

  @override
  Future<Either<ProfileFailure, Profile>> getMyProfile() async => getResult;

  @override
  Future<Either<ProfileFailure, Profile>> updateMyProfile({
    String? displayName,
    String? locale,
    String? themeMode,
    String? avatarUrl,
  }) async {
    updateCalls++;
    lastDisplayName = displayName;
    lastLocale = locale;
    lastThemeMode = themeMode;
    lastAvatarUrl = avatarUrl;
    return updateResult;
  }

  @override
  Future<Either<ProfileFailure, Profile>> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploadAvatarCalls++;
    lastAvatarContentType = contentType;
    return uploadAvatarResult;
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

  // PNG canonico minimo (firma + 0s). Pasa el validador de magic
  // bytes y permite testear el path feliz del notifier.
  Uint8List validPngBytes() => Uint8List.fromList([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, // firma PNG
        0x00, 0x00, 0x00, 0x0d, // payload arbitrario
      ]);

  // JPEG JFIF canonico minimo (4 bytes de firma + padding).
  Uint8List validJpegBytes() => Uint8List.fromList([
        0xff, 0xd8, 0xff, 0xe0, // firma JFIF
        0x00, 0x10, 0x4a, 0x46, 0x49, 0x46,
      ]);

  test('uploadAvatar calls repo and updates the profile', () async {
    await waitLoad();
    final before = state().savedTick;
    await notifier().uploadAvatar(validPngBytes(), 'image/png');
    expect(repo.uploadAvatarCalls, 1);
    expect(repo.lastAvatarContentType, 'image/png');
    expect(state().profile?.avatarUrl, 'https://example.com/a.png?v=1');
    expect(state().savedTick, before + 1);
    expect(state().status, ProfileSettingsStatus.ready);
  });

  test('uploadAvatar failure (Storage error) surfaces the failure', () async {
    await waitLoad();
    repo.uploadAvatarResult = const Left(ProfileUnknown());
    await notifier().uploadAvatar(validJpegBytes(), 'image/jpeg');
    expect(state().failure, isA<ProfileUnknown>());
    expect(state().status, ProfileSettingsStatus.ready);
  });

  test('uploadAvatar rechaza bytes sin firma valida sin tocar Storage',
      () async {
    await waitLoad();
    // Bytes basura (no son PNG/JPEG/GIF/WEBP). Aunque declaramos
    // image/png, el magic-bytes gate los rechaza ANTES de invocar la
    // repo. Defensa contra MIME spoofing.
    await notifier().uploadAvatar(
      Uint8List.fromList([0x4d, 0x5a, 0x90, 0x00]), // PE header (.exe)
      'image/png',
    );
    expect(repo.uploadAvatarCalls, 0); // NO se llama el repo
    expect(state().failure, isA<ProfileInvalidImage>());
    expect(state().status, ProfileSettingsStatus.ready);
  });

  test('uploadAvatar rechaza MIME fuera de la whitelist', () async {
    await waitLoad();
    // image/svg+xml NO esta permitido (XSS vector). Aunque los bytes
    // empiecen con algo razonable, el gate lo rechaza.
    await notifier().uploadAvatar(
      Uint8List.fromList([0x3c, 0x73, 0x76, 0x67]), // "<svg"
      'image/svg+xml',
    );
    expect(repo.uploadAvatarCalls, 0);
    expect(state().failure, isA<ProfileInvalidImage>());
  });
}
