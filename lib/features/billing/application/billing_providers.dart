import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/observability/analytics_service.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/utils/log_context.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';

import '../data/billing_datasource.dart';
import '../domain/entitlements.dart';
import '../domain/invoice.dart';
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

/// Facturas del tenant activo, ordenadas de más reciente a más antigua.
/// Empty si no hay tenant activo o si el tenant aún no ha pasado por
/// checkout (no tiene Stripe customer).
final myInvoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  final ds = ref.watch(billingDataSourceProvider);
  try {
    return await ds.listInvoices(tenantId: tenantId);
  } on BillingException {
    return const [];
  }
});

bool entitlementCapability(WidgetRef ref, String key, {bool fallback = false}) {
  final e = ref.watch(currentEntitlementsProvider).valueOrNull
      ?? const Entitlements.empty();
  return e.capability(key, fallback: fallback);
}

// ─── Acciones (Stripe checkout / portal) ─────────────────────────────────

/// Lanza el flujo de checkout: invoca la Edge Function, recibe la URL de
/// Stripe Checkout y devuelve la URL para que la UI redirija. La UI debe
/// llamar `html.window.location.href = url` (web) o `url_launcher` (mobile).
///
/// Devuelve la URL o `null` si falla. La excepción [BillingException] se
/// captura aquí y se loguea; la UI inspecciona el provider state para
/// mostrar el error apropiado.
Future<String?> launchCheckout(
  WidgetRef ref, {
  required String tenantId,
  required String planSlug,
  required String billingPeriod,
  required String successUrl,
  required String cancelUrl,
}) async {
  return LogContext.run<String?>(
    tags: {
      'flow': 'checkout',
      'tenant_id': tenantId,
      'plan_slug': planSlug,
      'billing_period': billingPeriod,
    },
    () async {
      final ds = ref.read(billingDataSourceProvider);
      final analytics = ref.read(analyticsServiceProvider);
      analytics.trackSync(
        'checkout_started',
        properties: {'plan_slug': planSlug, 'billing_period': billingPeriod},
      );
      try {
        final result = await ds.createCheckoutSession(
          tenantId: tenantId,
          planSlug: planSlug,
          billingPeriod: billingPeriod,
          successUrl: successUrl,
          cancelUrl: cancelUrl,
        );
        return result.url;
      } catch (e) {
        analytics.trackSync(
          'checkout_failed',
          properties: {
            'reason': e is BillingException ? e.code : 'unknown',
          },
        );
        if (kDebugMode) debugPrint('Checkout error: $e');
        rethrow;
      }
    },
  );
}

/// Abre Customer Portal. Devuelve la URL para redirigir (igual que
/// [launchCheckout]).
Future<String?> launchCustomerPortal(
  WidgetRef ref, {
  required String tenantId,
  required String returnUrl,
}) async {
  final ds = ref.read(billingDataSourceProvider);
  final analytics = ref.read(analyticsServiceProvider);
  analytics.trackSync('customer_portal_opened');
  try {
    return await ds.createCustomerPortalSession(
      tenantId: tenantId,
      returnUrl: returnUrl,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('Portal error: $e');
    rethrow;
  }
}
