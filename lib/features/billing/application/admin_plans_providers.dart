import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/admin_plans_datasource.dart';
import '../domain/plan.dart';
import 'billing_providers.dart';

final adminPlansDataSourceProvider = Provider<AdminPlansDataSource>((ref) {
  return AdminPlansDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de TODOS los planes (también inactivos). Solo accesible si el
/// caller es admin — el cliente lo asume (la pantalla está bajo el guard
/// admin del router); si no lo fuera, RLS le devolvería solo los activos.
final allPlansAdminProvider = FutureProvider<List<Plan>>((ref) async {
  final ds = ref.watch(adminPlansDataSourceProvider);
  return ds.listAllPlans();
});

/// Llamado tras editar un plan — invalida tanto la lista admin como la
/// pública (que verá los cambios de nombre/descripción).
void invalidatePlanCaches(WidgetRef ref) {
  ref
    ..invalidate(allPlansAdminProvider)
    ..invalidate(plansProvider)
    ..invalidate(currentPlanProvider)
    ..invalidate(currentEntitlementsProvider);
}
