import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso a `public.audit_logs`. La RLS limita lo que el cliente puede
/// hacer: insert/select solo de sus propias filas.
class AuditLogDataSource {
  const AuditLogDataSource(this._client);

  final SupabaseClient _client;

  static const String _table = 'audit_logs';

  /// Inserta una entrada. Lanza si no hay sesión (RLS rechaza el insert).
  Future<void> insert({
    required String event,
    Map<String, dynamic>? metadata,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return; // sin sesión, no podemos auditar nada.
    await _client.from(_table).insert({
      'user_id': userId,
      'event': event,
      if (metadata != null) 'metadata': metadata,
    });
  }

  /// Últimas [limit] entradas del usuario actual, ordenadas por fecha
  /// descendente.
  Future<List<Map<String, dynamic>>> listMyEntries({int limit = 100}) async {
    final data = await _client
        .from(_table)
        .select()
        .order('occurred_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data as List);
  }
}
