import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/admin_coupons_datasource.dart';
import '../domain/coupon.dart';
import '../domain/promotion_code.dart';

final adminCouponsDataSourceProvider = Provider<AdminCouponsDataSource>((ref) {
  return AdminCouponsDataSource(ref.watch(supabaseClientProvider));
});

/// Estado del catálogo admin: {coupons, promotionCodes}. Se invalida tras
/// cada create/deactivate desde la pantalla.
final adminCouponsListProvider = FutureProvider<
    ({List<Coupon> coupons, List<PromotionCode> promotionCodes})>((ref) async {
  final ds = ref.watch(adminCouponsDataSourceProvider);
  return ds.list();
});
