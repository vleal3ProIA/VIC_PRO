import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/feature_flag.dart';

/// Acceso al sistema de flags. Tres operaciones:
///
/// - **Lectura efectiva** (`fetchMine`): vía la RPC `my_feature_flags`
///   que resuelve overrides + rollout + global en una sola query.
/// - **Listado admin** (`fetchAllDefinitions`): vía SELECT con RLS
///   (solo admin global puede ver; el resto recibe lista vacía).
/// - **Update admin** (`update`): vía UPDATE con RLS.
class FeatureFlagsDataSource {
  const FeatureFlagsDataSource(this._client);

  final SupabaseClient _client;

  /// Devuelve el estado efectivo de TODOS los flags para el usuario actual
  /// y el [tenantId] opcionalmente activo. La RPC ya resuelve overrides.
  Future<List<FeatureFlag>> fetchMine({String? tenantId}) async {
    final data = await _client.rpc<List<dynamic>>(
      'my_feature_flags',
      params: {'p_tenant_id': tenantId},
    );
    return data
        .map((row) => FeatureFlag.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Definiciones globales — RLS solo deja ver al admin global. Otros
  /// usuarios reciben `[]` sin error.
  Future<List<FeatureFlagDefinition>> fetchAllDefinitions() async {
    final data = await _client
        .from('feature_flags')
        .select()
        .order('key');
    return (data as List)
        .map(
          (row) => FeatureFlagDefinition.fromMap(row as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  /// Actualiza un flag (toggle, rollout %, descripción, valor). RLS exige
  /// admin global; los demás reciben 0 filas afectadas.
  Future<void> update({
    required String key,
    bool? enabled,
    int? rolloutPercentage,
    String? description,
    Map<String, dynamic>? value,
  }) async {
    final patch = <String, dynamic>{
      if (enabled != null) 'enabled': enabled,
      if (rolloutPercentage != null) 'rollout_percentage': rolloutPercentage,
      if (description != null) 'description': description,
      if (value != null) 'value': value,
    };
    if (patch.isEmpty) return;
    await _client.from('feature_flags').update(patch).eq('key', key);
  }
}
