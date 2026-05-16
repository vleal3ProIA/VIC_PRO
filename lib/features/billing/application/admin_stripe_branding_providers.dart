import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/admin_stripe_branding_datasource.dart';
import '../domain/stripe_branding.dart';

final adminStripeBrandingDataSourceProvider =
    Provider<AdminStripeBrandingDataSource>((ref) {
  return AdminStripeBrandingDataSource(ref.watch(supabaseClientProvider));
});

/// Estado actual del branding Stripe de la plataforma. Se invalida tras
/// cada update/upload para refrescar la pantalla admin.
final stripeBrandingProvider = FutureProvider<StripeBranding>((ref) async {
  final ds = ref.watch(adminStripeBrandingDataSourceProvider);
  return ds.get();
});
