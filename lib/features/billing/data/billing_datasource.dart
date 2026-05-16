import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entitlements.dart';
import '../domain/invoice.dart';
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

  /// Crea una sesión de Stripe Checkout **hosted** y devuelve la URL. La UI
  /// redirige al usuario a esa URL — Stripe maneja el pago y al terminar
  /// manda al `successUrl` (o `cancelUrl` si abandona).
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
        'ui_mode': 'hosted',
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

  /// Crea una sesión **embedded** y devuelve el `client_secret` para que la
  /// UI monte el widget de Stripe en su propia página (sin redirect).
  /// `returnUrl` es donde Stripe redirige tras éxito (sustituye al
  /// `success_url` del hosted; no hay `cancel_url` en embedded — el usuario
  /// simplemente cierra la página).
  Future<({String clientSecret, String sessionId, String? publishableKey})>
      createEmbeddedCheckoutSession({
    required String tenantId,
    required String planSlug,
    required String billingPeriod,
    required String returnUrl,
    String? stripePromotionCodeId,
  }) async {
    final response = await _client.functions.invoke(
      'stripe-checkout',
      body: {
        'tenant_id': tenantId,
        'plan_slug': planSlug,
        'billing_period': billingPeriod,
        'success_url': returnUrl,
        'ui_mode': 'embedded',
        if (stripePromotionCodeId != null)
          'stripe_promotion_code_id': stripePromotionCodeId,
      },
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) throw const BillingException('empty_response');
    if (payload['error'] != null) {
      throw BillingException(payload['error'] as String);
    }
    return (
      clientSecret: payload['client_secret'] as String,
      sessionId: payload['session_id'] as String,
      publishableKey: payload['publishable_key'] as String?,
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

  /// Lista las últimas [limit] facturas del Stripe customer del tenant.
  /// Si el tenant no tiene customer (nunca ha pagado), devuelve `[]`.
  Future<List<Invoice>> listInvoices({
    required String tenantId,
    int limit = 20,
  }) async {
    final response = await _client.functions.invoke(
      'stripe-invoices',
      body: {'action': 'list', 'tenant_id': tenantId, 'limit': limit},
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) throw const BillingException('empty_response');
    if (payload['error'] != null) {
      throw BillingException(payload['error'] as String);
    }
    final list = payload['invoices'] as List?;
    if (list == null) return const [];
    return list
        .map((row) => Invoice.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  // ─── Subscription management (sin Customer Portal) ──────────────────────

  /// Cancela la sub al final del periodo facturado.
  Future<void> cancelSubscription(String subscriptionId) async {
    await _invokeSubUpdate({
      'action': 'cancel',
      'subscription_id': subscriptionId,
    });
  }

  /// Deshace una cancelación pendiente.
  Future<void> reactivateSubscription(String subscriptionId) async {
    await _invokeSubUpdate({
      'action': 'reactivate',
      'subscription_id': subscriptionId,
    });
  }

  /// Cancela inmediatamente (el user pierde acceso al momento).
  Future<void> cancelSubscriptionNow(String subscriptionId) async {
    await _invokeSubUpdate({
      'action': 'cancel_now',
      'subscription_id': subscriptionId,
    });
  }

  /// Cambia plan y/o periodo. Stripe aplica proration automáticamente.
  Future<void> changeSubscriptionPlan({
    required String subscriptionId,
    required String newPlanSlug,
    required String newBillingPeriod,
  }) async {
    await _invokeSubUpdate({
      'action': 'change_plan',
      'subscription_id': subscriptionId,
      'new_plan_slug': newPlanSlug,
      'new_billing_period': newBillingPeriod,
    });
  }

  /// Estima cuánto se cobra/se acredita al aplicar el cambio AHORA.
  /// `amountDueCents` negativo = crédito; positivo = se cobrará.
  Future<ChangePlanPreview> previewChangePlan({
    required String subscriptionId,
    required String newPlanSlug,
    required String newBillingPeriod,
  }) async {
    final payload = await _invokeSubUpdate({
      'action': 'preview_change_plan',
      'subscription_id': subscriptionId,
      'new_plan_slug': newPlanSlug,
      'new_billing_period': newBillingPeriod,
    });
    return ChangePlanPreview(
      amountDueCents: (payload['amount_due'] as int?) ?? 0,
      currency: (payload['currency'] as String?) ?? 'EUR',
    );
  }

  Future<Map<String, dynamic>> _invokeSubUpdate(
    Map<String, dynamic> body,
  ) async {
    final response = await _client.functions.invoke(
      'stripe-subscription-update',
      body: body,
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) throw const BillingException('empty_response');
    if (payload['error'] != null) {
      throw BillingException(payload['error'] as String);
    }
    return payload;
  }
}

/// Estimación de proration al cambiar de plan.
class ChangePlanPreview {
  const ChangePlanPreview({
    required this.amountDueCents,
    required this.currency,
  });

  /// Negativo = crédito; positivo = cargo inmediato.
  final int amountDueCents;
  final String currency;

  /// Formato "+€12,34" o "−€8,50" o "€0".
  String formatAmount() {
    final isNeg = amountDueCents < 0;
    final cents = amountDueCents.abs();
    final euros = cents / 100;
    final symbol = switch (currency.toUpperCase()) {
      'EUR' => '€',
      'USD' => r'$',
      'GBP' => '£',
      _ => currency.toUpperCase(),
    };
    final formatted = euros == euros.roundToDouble()
        ? euros.toStringAsFixed(0)
        : euros.toStringAsFixed(2);
    if (amountDueCents == 0) return '${symbol}0';
    return '${isNeg ? '−' : '+'}$symbol$formatted';
  }

  bool get isCharge => amountDueCents > 0;
  bool get isCredit => amountDueCents < 0;
}

/// Excepción con `code` para mapear a mensajes localizados en la UI.
class BillingException implements Exception {
  const BillingException(this.code);
  final String code;
  @override
  String toString() => 'BillingException($code)';
}
