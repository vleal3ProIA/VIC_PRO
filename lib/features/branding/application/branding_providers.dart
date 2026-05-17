import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/branding_datasource.dart';
import '../domain/app_branding.dart';

final brandingDataSourceProvider = Provider<BrandingDataSource>((ref) {
  return BrandingDataSource(ref.watch(supabaseClientProvider));
});

/// Branding actual del deploy. Se hidrata al boot y se invalida
/// tras cualquier update desde `/admin/app-branding` o `/setup`.
///
/// Es **público**: la RLS lo permite incluso para anon, así que
/// `WelcomePage` puede pintar el nombre comercial antes del login.
final appBrandingProvider = FutureProvider<AppBranding>((ref) async {
  final ds = ref.watch(brandingDataSourceProvider);
  return ds.fetch();
});

/// Helper síncrono que devuelve el branding ya cargado o el fallback
/// mientras carga. Útil donde no quieras hacer `.when(loading: ...)`
/// (ej. en el AppBar para evitar parpadeos).
final brandingOrFallbackProvider = Provider<AppBranding>((ref) {
  return ref.watch(appBrandingProvider).valueOrNull ?? AppBranding.fallback;
});
