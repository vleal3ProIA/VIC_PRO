import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/tenant_datasource.dart';
import '../domain/tenant.dart';

/// Clave de SharedPreferences para recordar el último tenant activo del
/// usuario entre recargas. Si el id guardado ya no existe (el usuario salió
/// del tenant, se borró, etc.), defaulteamos al primero de la lista.
const _kCurrentTenantKey = 'current_tenant_id_v1';

final tenantDataSourceProvider = Provider<TenantDataSource>((ref) {
  return TenantDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de tenants donde el usuario es miembro. Se recalcula al cambiar
/// la sesión (login/logout).
final myTenantsProvider = FutureProvider<List<Tenant>>((ref) async {
  final authed = ref.watch(isAuthenticatedProvider);
  if (!authed) return const [];
  final ds = ref.watch(tenantDataSourceProvider);
  return ds.listMyTenants();
});

/// Tenant activo del usuario. Lógica de resolución:
///
/// 1. Si SharedPreferences tiene un `current_tenant_id` y ese id está en
///    la lista de tenants del usuario → ese es el activo.
/// 2. Si no, el primer tenant de la lista (que viene con personales al
///    final, así que será el "real" si lo hay; o el personal si solo tiene
///    ese).
/// 3. Si no hay sesión → `null`.
///
/// El notifier expone `setCurrent(id)` para que el usuario cambie de tenant
/// y la preferencia se persista.
final currentTenantProvider =
    NotifierProvider<CurrentTenantNotifier, AsyncValue<Tenant?>>(
  CurrentTenantNotifier.new,
);

class CurrentTenantNotifier extends Notifier<AsyncValue<Tenant?>> {
  @override
  AsyncValue<Tenant?> build() {
    // Lee la lista y resuelve el activo. Mientras la lista carga,
    // devolvemos `AsyncValue.loading`.
    final tenantsAsync = ref.watch(myTenantsProvider);
    return tenantsAsync.when(
      loading: () => const AsyncLoading(),
      error: AsyncError<Tenant?>.new,
      data: (tenants) {
        if (tenants.isEmpty) return const AsyncData(null);
        final prefs = ref.read(sharedPreferencesProvider);
        final saved = prefs.getString(_kCurrentTenantKey);
        final match = tenants.firstWhere(
          (Tenant t) => t.id == saved,
          orElse: () => tenants.first,
        );
        return AsyncData<Tenant?>(match);
      },
    );
  }

  /// Cambia el tenant activo. Persiste la preferencia y dispara una
  /// reconstrucción inmediata.
  Future<void> setCurrent(String tenantId) async {
    final tenants = await ref.read(myTenantsProvider.future);
    final target = tenants.firstWhere(
      (t) => t.id == tenantId,
      orElse: () =>
          throw StateError('Tenant $tenantId no está en la lista del usuario'),
    );
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kCurrentTenantKey, tenantId);
    state = AsyncData(target);
  }

  /// Limpia la preferencia (típicamente al hacer logout). El próximo build
  /// recalculará desde cero la próxima vez que haya sesión.
  Future<void> clear() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_kCurrentTenantKey);
  }
}

/// Helper síncrono: el id del tenant activo o `null`. Útil para enriquecer
/// logs/analytics sin tener que esperar al async.
final currentTenantIdProvider = Provider<String?>((ref) {
  return ref.watch(currentTenantProvider).valueOrNull?.id;
});

/// Re-export para que la clave de SharedPreferences sea visible a los tests
/// sin duplicar la constante.
const currentTenantPrefsKey = _kCurrentTenantKey;
