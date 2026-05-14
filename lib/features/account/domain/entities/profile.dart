import 'package:flutter/material.dart';

import 'package:myapp/features/account/domain/entities/user_role.dart';

/// Perfil del usuario, mapeado 1:1 con la fila de `public.profiles` en
/// Supabase. El trigger `handle_new_user` la crea al registrarse.
class Profile {
  const Profile({
    required this.id,
    required this.locale,
    required this.themeMode,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.role = UserRole.user,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      username: map['username'] as String?,
      displayName: map['display_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      locale: (map['locale'] as String?) ?? 'en',
      themeMode: (map['theme_mode'] as String?) ?? 'system',
      role: UserRole.fromString(map['role'] as String?),
    );
  }

  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  /// Rol del usuario (`admin` | `user`). Viene de `profiles.role`.
  final UserRole role;

  /// Código ISO del idioma preferido ('es', 'en', …). Coincide con
  /// `profiles.locale`.
  final String locale;

  /// 'system' | 'light' | 'dark'. Coincide con `profiles.theme_mode`.
  final String themeMode;

  ThemeMode get themeModeEnum => switch (themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Locale get localeObj => Locale(locale);

  /// Nombre a mostrar: displayName > username > fallback.
  String get effectiveName =>
      (displayName?.trim().isNotEmpty ?? false)
          ? displayName!.trim()
          : (username?.trim().isNotEmpty ?? false)
              ? username!.trim()
              : 'user';

  Profile copyWith({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? locale,
    String? themeMode,
    UserRole? role,
  }) {
    return Profile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      locale: locale ?? this.locale,
      themeMode: themeMode ?? this.themeMode,
      role: role ?? this.role,
    );
  }
}
