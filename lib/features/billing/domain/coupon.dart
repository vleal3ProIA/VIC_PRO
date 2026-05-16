import 'package:meta/meta.dart';

/// Duración del descuento de un cupón. Espeja `coupon_duration` de Postgres
/// y `duration` de Stripe Coupons.
enum CouponDuration {
  /// El descuento aplica solo al primer pago.
  once,

  /// El descuento aplica durante N meses consecutivos
  /// (`durationInMonths`).
  repeating,

  /// El descuento aplica para siempre (mientras dure la suscripción).
  forever;

  static CouponDuration fromString(String raw) {
    switch (raw) {
      case 'repeating':
        return CouponDuration.repeating;
      case 'forever':
        return CouponDuration.forever;
      default:
        return CouponDuration.once;
    }
  }

  String get apiValue => name;
}

/// Cupón de descuento — la "regla" de descuento. No se canjea directo: el
/// cliente canjea un `PromotionCode` que apunta a este cupón.
@immutable
class Coupon {
  const Coupon({
    required this.id,
    required this.stripeCouponId,
    required this.name,
    required this.percentOff,
    required this.amountOffCents,
    required this.currency,
    required this.duration,
    required this.durationInMonths,
    required this.maxRedemptions,
    required this.redeemBy,
    required this.appliesToPlanSlugs,
    required this.isActive,
    required this.timesRedeemed,
    required this.createdAt,
  });

  factory Coupon.fromMap(Map<String, dynamic> m) {
    DateTime? parseTs(Object? v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return Coupon(
      id: m['id'] as String,
      stripeCouponId: m['stripe_coupon_id'] as String?,
      name: m['name'] as String,
      percentOff: (m['percent_off'] as num?)?.toDouble(),
      amountOffCents: m['amount_off_cents'] as int?,
      currency: m['currency'] as String?,
      duration: CouponDuration.fromString(m['duration'] as String),
      durationInMonths: m['duration_in_months'] as int?,
      maxRedemptions: m['max_redemptions'] as int?,
      redeemBy: parseTs(m['redeem_by']),
      appliesToPlanSlugs:
          (m['applies_to_plan_slugs'] as List?)?.cast<String>(),
      isActive: m['is_active'] as bool? ?? true,
      timesRedeemed: m['times_redeemed'] as int? ?? 0,
      createdAt: parseTs(m['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String? stripeCouponId;
  final String name;

  /// Exactamente uno de `percentOff` / `amountOffCents` es no-null.
  final double? percentOff;
  final int? amountOffCents;

  /// Solo no-null si `amountOffCents` no-null.
  final String? currency;

  final CouponDuration duration;
  final int? durationInMonths;
  final int? maxRedemptions;
  final DateTime? redeemBy;

  /// `null` = aplica a todos los planes activos. Lista no-vacía = solo a
  /// los slugs indicados.
  final List<String>? appliesToPlanSlugs;
  final bool isActive;
  final int timesRedeemed;
  final DateTime createdAt;

  bool get isPercent => percentOff != null;
  bool get isFixed => amountOffCents != null;

  /// Etiqueta humana corta — `20% off`, `5,00 €`, etc.
  String formatDiscount() {
    if (isPercent) {
      final p = percentOff!;
      return p == p.roundToDouble()
          ? '${p.toStringAsFixed(0)}%'
          : '${p.toStringAsFixed(2)}%';
    }
    final amt = amountOffCents! / 100.0;
    final sym = _currencySymbol(currency);
    return '${amt.toStringAsFixed(2)} $sym';
  }

  static String _currencySymbol(String? c) {
    switch (c) {
      case 'USD':
        return r'$';
      case 'GBP':
        return '£';
      case 'EUR':
      default:
        return '€';
    }
  }
}
