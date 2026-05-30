// ============================================================================
// admin · providers · PublicDomainSources
// ----------------------------------------------------------------------------
// Providers Riverpod alrededor de `PublicDomainSourcesDataSource`. La pagina
// `/admin/public-domain-sources` los usa para listar + invalidar tras
// create/update/delete.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/public_domain_sources_datasource.dart';
import '../domain/public_domain_source.dart';

final publicDomainSourcesDataSourceProvider =
    Provider<PublicDomainSourcesDataSource>((ref) {
  return PublicDomainSourcesDataSource(ref.watch(supabaseClientProvider));
});

/// Listado COMPLETO (activas + inactivas) — para el panel admin CRUD.
final publicDomainSourcesAllProvider =
    FutureProvider<List<PublicDomainSource>>((ref) {
  return ref.watch(publicDomainSourcesDataSourceProvider).listAll();
});

/// Listado SOLO activas — para colorear chips en cualquier UI user-side
/// (la RLS permite el SELECT a authenticated).
final publicDomainSourcesEnabledProvider =
    FutureProvider<List<PublicDomainSource>>((ref) {
  return ref.watch(publicDomainSourcesDataSourceProvider).listEnabled();
});
