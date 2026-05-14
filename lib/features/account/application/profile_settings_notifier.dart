import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/domain/entities/profile.dart';
import 'package:myapp/features/account/domain/failures/profile_failure.dart';

enum ProfileSettingsStatus { loading, ready, saving, failure }

class ProfileSettingsState {
  const ProfileSettingsState({
    this.status = ProfileSettingsStatus.loading,
    this.profile,
    this.failure,
    this.savedTick = 0,
  });

  final ProfileSettingsStatus status;
  final Profile? profile;
  final ProfileFailure? failure;

  /// Se incrementa cada vez que se guarda con éxito — la UI lo usa para
  /// disparar un snackbar de confirmación.
  final int savedTick;

  bool get isSaving => status == ProfileSettingsStatus.saving;

  ProfileSettingsState copyWith({
    ProfileSettingsStatus? status,
    Profile? profile,
    ProfileFailure? failure,
    int? savedTick,
    bool clearFailure = false,
  }) {
    return ProfileSettingsState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      failure: clearFailure ? null : (failure ?? this.failure),
      savedTick: savedTick ?? this.savedTick,
    );
  }
}

class ProfileSettingsNotifier extends Notifier<ProfileSettingsState> {
  @override
  ProfileSettingsState build() {
    _load();
    return const ProfileSettingsState();
  }

  Future<void> _load() async {
    final result = await ref.read(profileRepositoryProvider).getMyProfile();
    result.match(
      (failure) => state = state.copyWith(
        status: ProfileSettingsStatus.failure,
        failure: failure,
      ),
      (profile) => state = state.copyWith(
        status: ProfileSettingsStatus.ready,
        profile: profile,
      ),
    );
  }

  Future<void> retry() async {
    state = state.copyWith(
      status: ProfileSettingsStatus.loading,
      clearFailure: true,
    );
    await _load();
  }

  /// Guarda el display name en BD.
  Future<void> saveDisplayName(String displayName) async {
    await _update(displayName: displayName.trim());
  }

  /// Cambia el idioma: aplica inmediato en la UI (LocaleNotifier) y lo
  /// persiste en BD para que se sincronice entre dispositivos.
  Future<void> changeLocale(Locale locale) async {
    await ref.read(localeNotifierProvider.notifier).setLocale(locale);
    await _update(locale: locale.languageCode);
  }

  /// Cambia el tema: aplica inmediato (ThemeNotifier) y persiste en BD.
  Future<void> changeThemeMode(ThemeMode mode) async {
    await ref.read(themeNotifierProvider.notifier).setMode(mode);
    await _update(themeMode: mode.name);
  }

  Future<void> _update({
    String? displayName,
    String? locale,
    String? themeMode,
  }) async {
    final current = state.profile;
    if (current == null) return;
    state = state.copyWith(
      status: ProfileSettingsStatus.saving,
      clearFailure: true,
    );
    final result = await ref.read(profileRepositoryProvider).updateMyProfile(
          displayName: displayName,
          locale: locale,
          themeMode: themeMode,
        );
    result.match(
      (failure) => state = state.copyWith(
        status: ProfileSettingsStatus.ready,
        failure: failure,
      ),
      (profile) {
        state = state.copyWith(
          status: ProfileSettingsStatus.ready,
          profile: profile,
          savedTick: state.savedTick + 1,
        );
        // Refresca el provider global del perfil para que otras pantallas
        // (Home, etc.) vean los cambios.
        ref.invalidate(myProfileProvider);
      },
    );
  }
}

final profileSettingsNotifierProvider =
    NotifierProvider<ProfileSettingsNotifier, ProfileSettingsState>(
  ProfileSettingsNotifier.new,
);
