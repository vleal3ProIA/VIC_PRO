import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coupon.dart';
import '../domain/promotion_code.dart';

/// CRUD admin del catálogo de cupones + códigos promocionales.
/// Todas las llamadas pasan por la Edge Function `admin-coupons` que
/// sincroniza con Stripe en cada create/deactivate.
class AdminCouponsDataSource {
  const AdminCouponsDataSource(this._client);

  final SupabaseClient _client;

  /// Devuelve {coupons, promotionCodes}. Ambas listas vienen ordenadas
  /// por (activos primero, después por fecha desc).
  Future<({List<Coupon> coupons, List<PromotionCode> promotionCodes})> list() async {
    final payload = await _invoke({'action': 'list'});
    final coupons = ((payload['coupons'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Coupon.fromMap)
        .toList(growable: false);
    final codes = ((payload['promotion_codes'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PromotionCode.fromMap)
        .toList(growable: false);
    return (coupons: coupons, promotionCodes: codes);
  }

  Future<Coupon> createCoupon({
    required String name,
    required CouponDuration duration,
    double? percentOff,
    int? amountOffCents,
    String? currency,
    int? durationInMonths,
    int? maxRedemptions,
    DateTime? redeemBy,
    List<String>? appliesToPlanSlugs,
  }) async {
    final payload = await _invoke({
      'action': 'create_coupon',
      'name': name,
      if (percentOff != null) 'percent_off': percentOff,
      if (amountOffCents != null) 'amount_off_cents': amountOffCents,
      if (currency != null) 'currency': currency,
      'duration': duration.apiValue,
      if (durationInMonths != null) 'duration_in_months': durationInMonths,
      if (maxRedemptions != null) 'max_redemptions': maxRedemptions,
      if (redeemBy != null) 'redeem_by': redeemBy.toUtc().toIso8601String(),
      if (appliesToPlanSlugs != null && appliesToPlanSlugs.isNotEmpty)
        'applies_to_plan_slugs': appliesToPlanSlugs,
    });
    return Coupon.fromMap(
      (payload['coupon'] as Map).cast<String, dynamic>(),
    );
  }

  Future<void> deactivateCoupon(String couponId) async {
    await _invoke({
      'action': 'deactivate_coupon',
      'coupon_id': couponId,
    });
  }

  Future<PromotionCode> createPromotionCode({
    required String couponId,
    required String code,
    int? maxRedemptions,
    DateTime? expiresAt,
    bool firstTimeTransaction = false,
  }) async {
    final payload = await _invoke({
      'action': 'create_promotion_code',
      'coupon_id': couponId,
      'code': code.toUpperCase(),
      if (maxRedemptions != null) 'max_redemptions': maxRedemptions,
      if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
      'first_time_transaction': firstTimeTransaction,
    });
    return PromotionCode.fromMap(
      (payload['promotion_code'] as Map).cast<String, dynamic>(),
    );
  }

  Future<void> deactivatePromotionCode(String promotionCodeId) async {
    await _invoke({
      'action': 'deactivate_promotion_code',
      'promotion_code_id': promotionCodeId,
    });
  }

  /// Wrapper común: convierte errores HTTP en `AdminCouponException` con
  /// detalle de Stripe si lo hay (igual patrón que admin-stripe-branding).
  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(
        'admin-coupons',
        body: body,
      );
      final data = res.data;
      if (data is! Map) {
        throw const AdminCouponException('empty_response');
      }
      final payload = data.cast<String, dynamic>();
      if (payload['error'] != null) {
        throw AdminCouponException(
          payload['error'] as String,
          detail: payload['detail'] as String?,
        );
      }
      return payload;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        final m = details.cast<String, dynamic>();
        final code = m['error'] as String?;
        if (code != null) {
          throw AdminCouponException(
            code,
            detail: m['detail'] as String?,
          );
        }
      }
      throw AdminCouponException(
        'http_${e.status}',
        detail: details is String ? details : details?.toString(),
      );
    }
  }
}

class AdminCouponException implements Exception {
  const AdminCouponException(this.code, {this.detail});
  final String code;
  final String? detail;
  @override
  String toString() => detail == null
      ? 'AdminCouponException($code)'
      : 'AdminCouponException($code: $detail)';
}
