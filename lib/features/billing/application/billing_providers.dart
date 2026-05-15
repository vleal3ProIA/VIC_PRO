import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';

import '../data/billing_datasource.dart';
import '../domain/entitlements.dart';
import '../domain/plan.dart';
import '../domain/tenant_subscription.dart';

final billingDataSourceProvider = Provider<BillingDataSource>((ref) {
  return BillingDataSource(ref.watch(supabaseClientProvider));
});

/// Catálogo público de planes (los `is_active = true`).
final plansProvider = FutureProvider<List<Plan>>((ref) async {
  final ds = ref.watch(billingDataSourceProvider);
  return ds.listActivePlans();
});

/// Suscripción viva del tenant activo. `null` si no hay tenant o no hay
/// suscripción.
final currentSubscriptionProvider =
    FutureProvider<TenantSubscription?>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return null;
  final ds = ref.watch(billingDataSourceProvider);
  return ds.currentSubscriptionFor(tenantId);
});

/// Plan asociado a la suscripción viva del tenant actual.
final currentPlanProvider = FutureProvider<Plan?>((ref) async {
  final sub = await ref.watch(currentSubscriptionProvider.future);
  if (sub == null) return null;
  final plans = await ref.watch(plansProvider.future);
  return plans.where((p) => p.id == sub.planId).firstOrNull;
});

/// Entitlements del tenant actual. Empty si no hay tenant o no hay
/// suscripción — la UI debe degradar amablemente.
final currentEntitlementsProvider =
    FutureProvider<Entitlements>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const Entitlements.empty();
  final ds = ref.watch(billingDataSourceProvider);
  return ds.entitlementsFor(tenantId);
});

/// Sugar sync — útil cuando solo necesitas leer una cuota concreta sin
/// pelearte con `AsyncValue`. Devuelve el fallback mientras carga.
int entitlementQuota(WidgetRef ref, String key, {int fallback = 0}) {
  final e = ref.watch(currentEntitlementsProvider).valueOrNull
      ?? const Entitlements.empty();
  return e.quota(key, fallback: fallback);
}

bool entitlementCapability(WidgetRef ref, String key, {bool fallback = false}) {
  final e = ref.watch(currentEntitlementsProvider).valueOrNull
      ?? const Entitlements.empty();
  return e.capability(key, fallback: fallback);
}
