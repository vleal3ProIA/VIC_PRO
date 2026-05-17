import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_branding.dart';

/// Acceso a `app_branding` (singleton). La fila existe siempre (la
/// crea la migración), así que `fetch` no devuelve null.
class BrandingDataSource {
  const BrandingDataSource(this._client);

  final SupabaseClient _client;

  /// Lee el único row de la tabla `app_branding`. SELECT público vía RLS
  /// → funciona incluso para anon (welcome page antes del login).
  Future<AppBranding> fetch() async {
    final data = await _client
        .from('app_branding')
        .select()
        .eq('id', true)
        .single();
    return AppBranding.fromMap(data);
  }

  /// Actualiza los campos pasados. Admin-only via RLS. No envíes
  /// `null` para campos que no quieres cambiar — pasa solo lo que
  /// cambie.
  Future<AppBranding> update(Map<String, dynamic> patch) async {
    if (patch.isEmpty) return fetch();
    final data = await _client
        .from('app_branding')
        .update(patch)
        .eq('id', true)
        .select()
        .single();
    return AppBranding.fromMap(data);
  }

  /// Llama al RPC que promociona al user actual a admin SI no existe
  /// ningún admin todavía. Devuelve `true` si efectivamente promovió,
  /// `false` si ya había admin (no-op idempotente).
  Future<bool> bootstrapFirstAdmin() async {
    final result = await _client.rpc<dynamic>('bootstrap_first_admin');
    return result == true;
  }
}
