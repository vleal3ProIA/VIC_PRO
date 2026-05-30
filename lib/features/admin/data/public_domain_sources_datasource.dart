// ============================================================================
// admin · data · PublicDomainSourcesDataSource
// ----------------------------------------------------------------------------
// CRUD basico sobre la tabla `public.public_domain_sources` (migracion 0079).
// La RLS de la tabla:
//   - SELECT: cualquier autenticado (asi la UI puede colorear chips).
//   - INSERT/UPDATE/DELETE: solo `is_super_admin()`.
// Por tanto los metodos mutadores fallan con `permission_denied` si quien
// los llama no es super. La UI los esconde detras del guard de
// `/admin/public-domain-sources`.
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/public_domain_source.dart';

class PublicDomainSourcesDataSource {
  const PublicDomainSourcesDataSource(this._client);

  final SupabaseClient _client;

  static const String _table = 'public_domain_sources';

  /// Todas las sources (activas e inactivas), ordenadas por `enabled desc`
  /// (activas primero) y luego `label asc`.
  Future<List<PublicDomainSource>> listAll() async {
    final data = await _client
        .from(_table)
        .select()
        .order('enabled', ascending: false)
        .order('label');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(PublicDomainSource.fromMap)
        .toList(growable: false);
  }

  /// Solo activas — usada para colorear chips a usuarios normales (RLS lo
  /// permite).
  Future<List<PublicDomainSource>> listEnabled() async {
    final data = await _client
        .from(_table)
        .select()
        .eq('enabled', true)
        .order('label');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(PublicDomainSource.fromMap)
        .toList(growable: false);
  }

  Future<PublicDomainSource> create({
    required String pattern,
    required String label,
    required PublicDomainMatchType matchType,
    String? notes,
  }) async {
    final uid = _client.auth.currentUser?.id;
    final data = await _client
        .from(_table)
        .insert({
          'pattern': pattern,
          'label': label,
          'match_type': matchTypeToWire(matchType),
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          if (uid != null) 'created_by': uid,
        })
        .select()
        .single();
    return PublicDomainSource.fromMap(data);
  }

  Future<PublicDomainSource> update({
    required String id,
    String? pattern,
    String? label,
    PublicDomainMatchType? matchType,
    String? notes,
    bool? enabled,
  }) async {
    final patch = <String, dynamic>{
      if (pattern != null) 'pattern': pattern,
      if (label != null) 'label': label,
      if (matchType != null) 'match_type': matchTypeToWire(matchType),
      if (notes != null) 'notes': notes.isEmpty ? null : notes,
      if (enabled != null) 'enabled': enabled,
    };
    final data = await _client
        .from(_table)
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    return PublicDomainSource.fromMap(data);
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    await _client.from(_table).update({'enabled': enabled}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
