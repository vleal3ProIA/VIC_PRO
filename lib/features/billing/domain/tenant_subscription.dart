import 'package:meta/meta.dart';

enum SubscriptionStatus {
  trialing,
  active,
  pastDue,
  canceled,
  incomplete;

  static SubscriptionStatus fromString(String v) => switch (v) {
        'trialing' => SubscriptionStatus.trialing,
        'past_due' => SubscriptionStatus.pastDue,
        'canceled' => SubscriptionStatus.canceled,
        'incomplete' => SubscriptionStatus.incomplete,
        _ => SubscriptionStatus.active,
      };

  /// True cuando el tenant tiene acceso pleno (no canceled ni incomplete).
  bool get isLive =>
      this == SubscriptionStatus.trialing ||
      this == SubscriptionStatus.active ||
      this == SubscriptionStatus.pastDue;
}

enum BillingPeriod {
  monthly,
  yearly;

  static BillingPeriod fromString(String v) =>
      v == 'yearly' ? BillingPeriod.yearly : BillingPeriod.monthly;

  String toDbString() => name;
}

/// Suscripción de un tenant a un plan. NO contiene los entitlements
/// directamente — esos viven en `Plan.features`. Se resuelve por la RPC
/// `tenant_entitlements(tenant_id)`.
@immutable
class TenantSubscription {
  const TenantSubscription({
    required this.id,
    required this.tenantId,
    required this.planId,
    required this.status,
    required this.billingPeriod,
    required this.createdAt,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.trialEnd,
    this.canceledAt,
    this.cancelAtPeriodEnd = false,
    this.stripeSubscriptionId,
    this.stripeCustomerId,
  });

  factory TenantSubscription.fromMap(Map<String, dynamic> map) {
    DateTime? parse(Object? raw) =>
        raw == null ? null : DateTime.parse(raw as String);
    return TenantSubscription(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      planId: map['plan_id'] as String,
      status: SubscriptionStatus.fromString(map['status'] as String),
      billingPeriod:
          BillingPeriod.fromString(map['billing_period'] as String),
      currentPeriodStart: parse(map['current_period_start']),
      currentPeriodEnd: parse(map['current_period_end']),
      trialEnd: parse(map['trial_end']),
      canceledAt: parse(map['canceled_at']),
      cancelAtPeriodEnd: (map['cancel_at_period_end'] as bool?) ?? false,
      stripeSubscriptionId: map['stripe_subscription_id'] as String?,
      stripeCustomerId: map['stripe_customer_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String tenantId;
  final String planId;
  final SubscriptionStatus status;
  final BillingPeriod billingPeriod;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? trialEnd;
  final DateTime? canceledAt;

  /// `true` cuando el cliente programó la cancelación pero todavía tiene
  /// acceso hasta `currentPeriodEnd`. La UI debe mostrar un banner del tipo
  /// "Tu plan termina el [fecha], reactiva para mantenerlo".
  final bool cancelAtPeriodEnd;

  final String? stripeSubscriptionId;
  final String? stripeCustomerId;
  final DateTime createdAt;
}
