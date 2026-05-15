import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';

import '../data/feature_flags_datasource.dart';
import '../domain/feature_flag.dart';

final featureFlagsDataSourceProvider =
    Provider<FeatureFlagsDataSource>((ref) {
  return FeatureFlagsDataSource(ref.watch(supabaseClientProvider));
});

/// Mapa `key → FeatureFlag` con el estado efectivo para el caller en el
/// tenant actual. Se recalcula cuando cambia la sesión o el tenant activo.
final myFeatureFlagsProvider =
    FutureProvider<Map<String, FeatureFlag>>((ref) async {
  final authed = ref.watch(isAuthenticatedProvider);
  if (!authed) return const {};
  final tenantId = ref.watch(currentTenantIdProvider);
  final ds = ref.watch(featureFlagsDataSourceProvider);
  final flags = await ds.fetchMine(tenantId: tenantId);
  return {for (final f in flags) f.key: f};
});

/// Lookup síncrono de un flag puntual. Devuelve `null` si aún cargando o
/// no existe. Patrón típico:
///
/// ```dart
/// final flag = ref.watch(featureFlagProvider('audit_log_visible'));
/// if (flag?.enabled ?? false) { ... }
/// ```
final featureFlagProvider =
    Provider.family<FeatureFlag?, String>((ref, key) {
  final map = ref.watch(myFeatureFlagsProvider).valueOrNull ?? const {};
  return map[key];
});

/// Sugar API: ¿está activo este flag? `false` mientras carga o si no existe.
final flagEnabledProvider = Provider.family<bool, String>((ref, key) {
  return ref.watch(featureFlagProvider(key))?.enabled ?? false;
});

/// Lista completa de definiciones (admin only). RLS filtra; los demás
/// reciben lista vacía sin error.
final featureFlagDefinitionsProvider =
    FutureProvider<List<FeatureFlagDefinition>>((ref) async {
  final ds = ref.watch(featureFlagsDataSourceProvider);
  return ds.fetchAllDefinitions();
});
