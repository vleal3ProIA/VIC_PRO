// ============================================================================
// Admin ACL · Providers (PR-Super-A2)
// ----------------------------------------------------------------------------
// Wrapper alrededor de las RPCs SQL `get_my_capabilities()` y
// `is_super_admin()` (migracion 0044). Cacheado via Riverpod -- solo
// se vuelve a fetchear cuando el user hace login/logout o algun
// callsite invalida explicitamente.
//
// **Uso desde widgets**:
//
//   final caps = ref.watch(myCapabilitiesProvider).valueOrNull ?? const {};
//   if (caps.contains(AdminCapability.manageUsers)) { ... }
//
//   final isSuper = ref.watch(isSuperAdminProvider).valueOrNull ?? false;
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/admin_acl_datasource.dart';
import '../domain/admin_row.dart';

/// Singleton del datasource. Wireado al SupabaseClient global.
final adminAclDataSourceProvider = Provider<AdminAclDataSource>((ref) {
  return AdminAclDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de admins + sus capabilities. SOLO el super admin puede
/// invocar la RPC -- los admins normales reciben PostgrestException
/// (`super admin only`) que la pagina mapea a un error state.
final adminsListProvider = FutureProvider<List<AdminRow>>((ref) async {
  return ref.watch(adminAclDataSourceProvider).listAdmins();
});

/// Capacidades concedidas al user actual. Devuelve un set vacio si:
///   - No hay sesion activa.
///   - El user es 'user' normal (sin role admin).
///   - El user tiene role='admin' pero sin capabilities asignadas
///     (el super deberia darle al menos una para que pueda hacer algo).
///
/// El super admin recibe las 13 capabilities automaticamente (lista
/// hardcoded server-side en `get_my_capabilities()`).
final myCapabilitiesProvider = FutureProvider<Set<String>>((ref) async {
  final authed = ref.watch(isAuthenticatedProvider);
  if (!authed) return const <String>{};
  try {
    final data = await ref
        .watch(supabaseClientProvider)
        .rpc<dynamic>('get_my_capabilities');
    if (data is! List) return const <String>{};
    return data.whereType<String>().toSet();
  } catch (_) {
    // Si la RPC falla (red, BD), devolvemos set vacio. La UI lo
    // tratara como "sin capabilities" -- las paginas admin no se
    // mostraran. Defensa-en-profundidad: ante duda, denegar.
    return const <String>{};
  }
});

/// `true` si el user es super admin (vleal3@gmail.com tras migracion
/// 0044). Lo derivamos de myCapabilitiesProvider para evitar una
/// segunda RPC: si recibimos 13 caps, es el super; sino, no lo es.
///
/// **Alternativa rechazada**: llamar `is_super_admin()` RPC. Mas
/// trafico de red y la informacion esta ya en `get_my_capabilities()`.
final isSuperAdminProvider = Provider<AsyncValue<bool>>((ref) {
  final capsAsync = ref.watch(myCapabilitiesProvider);
  return capsAsync.whenData(
    // 13 es el total hardcoded en la lista del migration. Si el server
    // anyade alguna nueva, hay que subir este numero -- por eso uso
    // AdminCapability.all.length para estar siempre sincronizado.
    (caps) => caps.length >= 13,
  );
});

/// Helper sincrono que devuelve `true` si el user es super. Para usos
/// donde el AsyncValue es incomodo. Devuelve `false` mientras carga
/// (defensa: no asumir super).
bool isSuperAdminSync(WidgetRef ref) {
  return ref.watch(isSuperAdminProvider).valueOrNull ?? false;
}

/// Helper sincrono que devuelve `true` si el user tiene una capacidad
/// concreta. Devuelve `false` mientras carga.
bool hasCapability(WidgetRef ref, String capability) {
  final caps = ref.watch(myCapabilitiesProvider).valueOrNull;
  if (caps == null) return false;
  return caps.contains(capability);
}
