import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/incidents_datasource.dart';
import '../domain/incident.dart';

final incidentsDataSourceProvider = Provider<IncidentsDataSource>((ref) {
  return IncidentsDataSource(ref.watch(supabaseClientProvider));
});

/// Incidentes activos publicados. Lo consumen el banner in-app y la
/// cabecera de `/status`. Se mantiene barato por el índice parcial
/// `incidents_active_idx`.
final activeIncidentsProvider = FutureProvider<List<Incident>>((ref) async {
  final ds = ref.watch(incidentsDataSourceProvider);
  return ds.listActive();
});

/// Histórico de incidentes publicados (últimos 30 días). Para la
/// página `/status`.
final incidentsHistoryProvider = FutureProvider<List<Incident>>((ref) async {
  final ds = ref.watch(incidentsDataSourceProvider);
  return ds.listHistory();
});

/// Lista TODO (incluidos borradores) — admin only.
final adminIncidentsProvider = FutureProvider<List<Incident>>((ref) async {
  final ds = ref.watch(incidentsDataSourceProvider);
  return ds.listAllForAdmin();
});

/// Overall status calculado a partir de [activeIncidentsProvider].
/// Devuelve `OverallStatus.operational` mientras carga (evita el flash
/// de "incidente desconocido" en el badge).
final overallStatusProvider = Provider<OverallStatus>((ref) {
  final async = ref.watch(activeIncidentsProvider);
  return computeOverallStatus(async.valueOrNull ?? const []);
});
