import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso fino a la tabla `public.profiles`. El mapeo a `ProfileFailure`
/// se hace en el repositorio.
class ProfileSupabaseDataSource {
  const ProfileSupabaseDataSource(this._client);

  final SupabaseClient _client;

  static const String _table = 'profiles';

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
  }) async {
    final patch = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (locale != null) 'locale': locale,
      if (themeMode != null) 'theme_mode': themeMode,
    };
    final data = await _client
        .from(_table)
        .update(patch)
        .eq('id', _currentUserId)
        .select()
        .single();
    return data;
  }
}
