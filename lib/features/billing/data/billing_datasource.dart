import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entitlements.dart';
import '../domain/plan.dart';
import '../domain/tenant_subscription.dart';

class BillingDataSource {
  const BillingDataSource(this._client);

  final SupabaseClient _client;

  /// Catálogo de planes activos (RLS deja ver todos los `is_active=true`).
  Future<List<Plan>> listActivePlans() async {
    final data = await _client
        .from('plans')
        .select()
        .eq('is_active', true)
        .order('position');
    return (data as List)
        .map((row) => Plan.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Suscripción "viva" del tenant (trialing/active/past_due/incomplete).
  /// Devuelve `null` si no hay ninguna.
  Future<TenantSubscription?> currentSubscriptionFor(String tenantId) async {
    final data = await _client
        .from('tenant_subscriptions')
        .select()
        .eq('tenant_id', tenantId)
        .inFilter('status', const ['trialing', 'active', 'past_due', 'incomplete'])
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return TenantSubscription.fromMap(data);
  }

  /// Entitlements del plan activo del tenant. Devuelve [Entitlements.empty]
  /// si no hay nada o el caller no es miembro (RLS).
  Future<Entitlements> entitlementsFor(String tenantId) async {
    final raw = await _client.rpc<Object?>(
      'tenant_entitlements',
      params: {'p_tenant_id': tenantId},
    );
    if (raw is Map<String, dynamic>) return Entitlements(raw);
    if (raw is Map) return Entitlements(Map<String, dynamic>.from(raw));
    return const Entitlements.empty();
  }

  /// Crea una sesión de Stripe Checkout y devuelve la URL. La UI redirige
  /// al usuario a esa URL — Stripe maneja el pago y al terminar manda al
  /// `successUrl` (o `cancelUrl` si abandona).
  ///
  /// Lanza [BillingException] con el `code` del backend si falla.
  Future<({String url, String sessionId})> createCheckoutSession({
    required String tenantId,
    required String planSlug,
    required String billingPeriod,
    required String successUrl,
    required String cancelUrl,
  }) async {
    final response = await _client.functions.invoke(
      'stripe-checkout',
      body: {
        'tenant_id': tenantId,
        'plan_slug': planSlug,
        'billing_period': billingPeriod,
        'success_url': successUrl,
        'cancel_url': cancelUrl,
      },
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) throw const BillingException('empty_response');
    if (payload['error'] != null) {
      throw BillingException(payload['error'] as String);
    }
    return (
      url: payload['url'] as String,
      sessionId: payload['session_id'] as String,
    );
  }

  /// Crea una sesión del Customer Portal de Stripe y devuelve su URL.
  Future<String> createCustomerPortalSession({
    required String tenantId,
    required String returnUrl,
  }) async {
    final response = await _client.functions.invoke(
      'stripe-portal',
      body: {'tenant_id': tenantId, 'return_url': returnUrl},
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) throw const BillingException('empty_response');
    if (payload['error'] != null) {
      throw BillingException(payload['error'] as String);
    }
    return payload['url'] as String;
  }
}

/// Excepción con `code` para mapear a mensajes localizados en la UI.
class BillingException implements Exception {
  const BillingException(this.code);
  final String code;
  @override
  String toString() => 'BillingException($code)';
}
