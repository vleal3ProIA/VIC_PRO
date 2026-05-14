import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso fino a la tabla `public.profiles`. El mapeo a `ProfileFailure`
/// se hace en el repositorio.
class ProfileSupabaseDataSource {
  const ProfileSupabaseDataSource(this._client);

  final SupabaseClient _client;

  static const String _table = 'profiles';
  static const String _avatarsBucket = 'avatars';

  String get _currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthException('No active session');
    }
    return id;
  }

  /// Devuelve la fila del perfil del usuario actual.
  Future<Map<String, dynamic>> fetchMyProfile() async {
    final data = await _client
        .from(_table)
        .select()
        .eq('id', _currentUserId)
        .single();
    return data;
  }

  /// Actualiza solo los campos pasados (los nulos se omiten). Devuelve la
  /// fila actualizada.
  Future<Map<String, dynamic>> updateMyProfile({
    String? displayName,
    String? locale,
    String? themeMode,
    String? avatarUrl,
  }) async {
    final patch = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (locale != null) 'locale': locale,
      if (themeMode != null) 'theme_mode': themeMode,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
    final data = await _client
        .from(_table)
        .update(patch)
        .eq('id', _currentUserId)
        .select()
        .single();
    return data;
  }

  /// Sube la imagen de avatar al bucket `avatars` en `{userId}/avatar`
  /// (sobrescribiendo el anterior) y devuelve la URL pública con un sufijo
  /// `?v=timestamp` para invalidar la caché del navegador.
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final path = '$_currentUserId/avatar';
    await _client.storage.from(_avatarsBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    final publicUrl =
        _client.storage.from(_avatarsBucket).getPublicUrl(path);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
