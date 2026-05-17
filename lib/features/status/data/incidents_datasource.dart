import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/incident.dart';

/// Acceso a la tabla `incidents`. Lecturas via RLS (anon ve solo
/// `published=true`; admin ve todo). CRUD admin-only via RLS.
class IncidentsDataSource {
  const IncidentsDataSource(this._client);

  final SupabaseClient _client;

  /// Lista incidentes activos publicados (status != resolved).
  /// Para el banner in-app y la cabecera de `/status`.
  Future<List<Incident>> listActive() async {
    final data = await _client
        .from('incidents')
        .select(
          'id, title, body, status, severity, components, '
          'started_at, resolved_at, published, created_at, updated_at',
        )
        .eq('published', true)
        .filter('resolved_at', 'is', null)
        .order('started_at', ascending: false);
    return _mapList(data);
  }

  /// Histórico de incidentes publicados (incluye resueltos). Por
  /// defecto últimos 30 días — suficiente para la página /status.
  Future<List<Incident>> listHistory({int days = 30}) async {
    final since =
        DateTime.now().subtract(Duration(days: days)).toUtc().toIso8601String();
    final data = await _client
        .from('incidents')
        .select(
          'id, title, body, status, severity, components, '
          'started_at, resolved_at, published, created_at, updated_at',
        )
        .eq('published', true)
        .gte('started_at', since)
        .order('started_at', ascending: false);
    return _mapList(data);
  }

  /// Lista TODOS los incidentes (incluye borradores) — admin only via
  /// RLS. Para la pantalla `/admin/incidents`.
  Future<List<Incident>> listAllForAdmin() async {
    final data = await _client
        .from('incidents')
        .select(
          'id, title, body, status, severity, components, '
          'started_at, resolved_at, published, created_at, updated_at',
        )
        .order('started_at', ascending: false);
    return _mapList(data);
  }

  Future<Incident> create({
    required String title,
    required String body,
    required IncidentStatus status,
    required IncidentSeverity severity,
    required List<String> components,
    DateTime? startedAt,
    bool published = false,
  }) async {
    final data = await _client
        .from('incidents')
        .insert({
          'title': title,
          'body': body,
          'status': incidentStatusToDb(status),
          'severity': incidentSeverityToDb(severity),
          'components': components,
          if (startedAt != null) 'started_at': startedAt.toIso8601String(),
          'published': published,
        })
        .select()
        .single();
    return Incident.fromMap(data);
  }

  Future<Incident> update({
    required String id,
    required String title,
    required String body,
    required IncidentStatus status,
    required IncidentSeverity severity,
    required List<String> components,
    required bool published,
    DateTime? startedAt,
  }) async {
    final data = await _client
        .from('incidents')
        .update({
          'title': title,
          'body': body,
          'status': incidentStatusToDb(status),
          'severity': incidentSeverityToDb(severity),
          'components': components,
          if (startedAt != null) 'started_at': startedAt.toIso8601String(),
          'published': published,
        })
        .eq('id', id)
        .select()
        .single();
    return Incident.fromMap(data);
  }

  Future<void> delete(String id) async {
    await _client.from('incidents').delete().eq('id', id);
  }

  List<Incident> _mapList(dynamic data) {
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Incident.fromMap)
        .toList(growable: false);
  }
}
