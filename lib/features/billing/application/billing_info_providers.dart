import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/billing_info_datasource.dart';
import '../domain/billing_info.dart';

final billingInfoDataSourceProvider =
    Provider<BillingInfoDataSource>((ref) {
  return BillingInfoDataSource(ref.watch(supabaseClientProvider));
});

/// Datos de facturación del usuario actual. Se recalcula al cambiar la
/// sesión. Empty si no hay sesión.
final myBillingInfoProvider = FutureProvider<BillingInfo>((ref) async {
  final authed = ref.watch(isAuthenticatedProvider);
  if (!authed) return BillingInfo.empty;
  final ds = ref.watch(billingInfoDataSourceProvider);
  return ds.fetchMine();
});

/// Sugar sync: ¿el usuario tiene billing info completa? Se usa para
/// gating en /billing/plans antes del Upgrade.
final billingInfoCompleteProvider = Provider<bool>((ref) {
  final info = ref.watch(myBillingInfoProvider).valueOrNull;
  return info?.isCompleteForBilling ?? false;
});
