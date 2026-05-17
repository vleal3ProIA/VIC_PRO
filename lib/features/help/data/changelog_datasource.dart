import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/changelog_entry.dart';

/// Acceso a las entradas del changelog. Lecturas via RLS (publicadas
/// para todos, borradores solo para admins). RPCs `mark_changelog_seen`
/// y `has_unseen_changelog` para el badge "What's new".
class ChangelogDataSource {
  const ChangelogDataSource(this._client);

  final SupabaseClient _client;

  /// Lista de entradas. RLS hace el filtrado:
  ///  - User normal: solo `publishedAt != null`.
  ///  - Admin: todo (incluidos borradores).
  ///
  /// [limit] por defecto 100 — suficiente para una primera versión
  /// sin paginación. Si crece, añadir cursor.
  Future<List<ChangelogEntry>> list({int limit = 100}) async {
    final data = await _client
        .from('changelog_entries')
        .select(
          'id, version, title, body, category, '
          'published_at, created_at, updated_at',
        )
        .order('published_at', ascending: false, nullsFirst: true)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(ChangelogEntry.fromMap)
        .toList(growable: false);
  }

  /// Crea una entrada nueva. Admin-only via RLS.
  Future<ChangelogEntry> create({
    required String title,
    required String body,
    required ChangelogCategory category,
    String? version,
    DateTime? publishedAt,
  }) async {
    final data = await _client
        .from('changelog_entries')
        .insert({
          if (version != null && version.isNotEmpty) 'version': version,
          'title': title,
          'body': body,
          'category': _categoryToDb(category),
          'published_at': publishedAt?.toIso8601String(),
        })
        .select()
        .single();
    return ChangelogEntry.fromMap(data);
  }

  /// Actualiza una entrada existente. Admin-only via RLS.
  Future<ChangelogEntry> update({
    required String id,
    required String title,
    required String body,
    required ChangelogCategory category,
    String? version,
    DateTime? publishedAt,
  }) async {
    final data = await _client
        .from('changelog_entries')
        .update({
          'version': (version != null && version.isNotEmpty) ? version : null,
          'title': title,
          'body': body,
          'category': _categoryToDb(category),
          'published_at': publishedAt?.toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return ChangelogEntry.fromMap(data);
  }

  /// Borra una entrada. Admin-only via RLS.
  Future<void> delete(String id) async {
    await _client.from('changelog_entries').delete().eq('id', id);
  }

  /// Marca el changelog como visto -> badge desaparece.
  Future<void> markSeen() async {
    await _client.rpc<dynamic>('mark_changelog_seen');
  }

  /// `true` si hay entradas publicadas posteriores a la última visita
  /// del user (o si nunca lo abrió).
  Future<bool> hasUnseen() async {
    final result = await _client.rpc<dynamic>('has_unseen_changelog');
    return result == true;
  }

  String _categoryToDb(ChangelogCategory c) {
    switch (c) {
      case ChangelogCategory.feature:
        return 'feature';
      case ChangelogCategory.improvement:
        return 'improvement';
      case ChangelogCategory.fix:
        return 'fix';
      case ChangelogCategory.security:
        return 'security';
    }
  }
}
