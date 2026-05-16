import 'package:meta/meta.dart';

/// Código alfanumérico canjeable por un descuento (apunta a un `Coupon`).
@immutable
class PromotionCode {
  const PromotionCode({
    required this.id,
    required this.stripePromotionCodeId,
    required this.couponId,
    required this.code,
    required this.maxRedemptions,
    required this.expiresAt,
    required this.firstTimeTransaction,
    required this.isActive,
    required this.timesRedeemed,
    required this.createdAt,
  });

  factory PromotionCode.fromMap(Map<String, dynamic> m) {
    DateTime? parseTs(Object? v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return PromotionCode(
      id: m['id'] as String,
      stripePromotionCodeId: m['stripe_promotion_code_id'] as String?,
      couponId: m['coupon_id'] as String,
      code: m['code'] as String,
      maxRedemptions: m['max_redemptions'] as int?,
      expiresAt: parseTs(m['expires_at']),
      firstTimeTransaction: m['first_time_transaction'] as bool? ?? false,
      isActive: m['is_active'] as bool? ?? true,
      timesRedeemed: m['times_redeemed'] as int? ?? 0,
      createdAt: parseTs(m['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String? stripePromotionCodeId;
  final String couponId;
  final String code;
  final int? maxRedemptions;
  final DateTime? expiresAt;
  final bool firstTimeTransaction;
  final bool isActive;
  final int timesRedeemed;
  final DateTime createdAt;
}

/// Resultado de validar un código promocional contra el backend antes del
/// checkout — lo que la UI muestra al cliente y lo que pasamos al
/// Stripe Checkout session.
@immutable
class AppliedPromotionCode {
  const AppliedPromotionCode({
    required this.promotionCodeId,
    required this.stripePromotionCodeId,
    required this.code,
    required this.percentOff,
    required this.amountOffCents,
    required this.currency,
    required this.duration,
    required this.durationInMonths,
    required this.appliesToPlanSlugs,
  });

  factory AppliedPromotionCode.fromValidatePayload(Map<String, dynamic> m) {
    final discount = (m['discount'] as Map).cast<String, dynamic>();
    return AppliedPromotionCode(
      promotionCodeId: m['promotion_code_id'] as String,
      stripePromotionCodeId: m['stripe_promotion_code_id'] as String,
      code: m['code'] as String,
      percentOff: (discount['percent_off'] as num?)?.toDouble(),
      amountOffCents: discount['amount_off_cents'] as int?,
      currency: discount['currency'] as String?,
      duration: discount['duration'] as String,
      durationInMonths: discount['duration_in_months'] as int?,
      appliesToPlanSlugs:
          (m['applies_to_plan_slugs'] as List?)?.cast<String>(),
    );
  }

  final String promotionCodeId;
  final String stripePromotionCodeId;
  final String code;
  final double? percentOff;
  final int? amountOffCents;
  final String? currency;
  final String duration;
  final int? durationInMonths;
  final List<String>? appliesToPlanSlugs;

  bool get isPercent => percentOff != null;

  /// Aplica el descuento sobre `priceCents` y devuelve el precio final
  /// en centavos. NOTA: solo es preview para mostrar al cliente; el
  /// cálculo definitivo lo hace Stripe en el Checkout.
  int applyToPriceCents(int priceCents) {
    if (isPercent) {
      final off = (priceCents * percentOff! / 100).round();
      final result = priceCents - off;
      return result < 0 ? 0 : result;
    }
    final result = priceCents - (amountOffCents ?? 0);
    return result < 0 ? 0 : result;
  }
}
