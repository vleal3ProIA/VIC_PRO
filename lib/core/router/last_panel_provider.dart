// ============================================================================
// last_panel_provider.dart · "Resume last Panel" — provider del redirect
// ----------------------------------------------------------------------------
// Lee `profiles.last_subject_id` + `last_node_id` del user actual (migracion
// 0085) para que el guard del router decida, en post-login, mandar al user
// directo a su ultimo Panel en vez de a /home.
//
// Sincronismo: `appRouterRedirect` es SYNC (lo exige go_router). Por eso
// el provider es un `FutureProvider` y el guard lee `valueOrNull` -- si
// todavia esta cargando, el redirect cae a /home (sin flash). Cuando
// resuelve, el `_AuthRefreshNotifier` del router detecta el cambio y
// re-evalua, mandando al user a su Panel.
//
// Invalidacion cross-user: el provider hace `ref.watch(currentUserProvider)`
// y deriva su key del user.id. Al hacer logout+login con otro user, el
// `userCacheGuardProvider` ya invalida `subjectsDataSourceProvider`, asi
// que el siguiente read va al backend con el JWT nuevo. Aqui ademas
// rebuild-eamos al cambiar de user (depende de `currentUserProvider`),
// asi nunca devolvemos el last-panel del user anterior.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/subjects/application/subjects_providers.dart';

/// Resultado inmutable de la query "ultimo Panel del user".
class LastPanelLocation {
  const LastPanelLocation({this.subjectId, this.nodeId});

  /// `null` => no hay sesion previa (user nuevo, o el FK on-delete-set-null
  /// se llevo el subject por delante).
  final String? subjectId;

  /// `null` => abrir el Panel sin nodo preseleccionado (la propia pagina
  /// elegira el nodo raiz, como hace en arranque normal).
  final String? nodeId;

  bool get hasPanel => subjectId != null;
}

/// Lee `profiles.last_subject_id` + `last_node_id` del user actual.
///
/// - Si no hay user (logout) -> emite `LastPanelLocation()` (sin panel).
/// - Si hay user pero el read falla (red caida, RLS) -> el provider
///   devuelve error y el guard cae a /home via `valueOrNull == null`.
///
/// El provider depende de `currentUserProvider`: al cambiar de user
/// Riverpod lo recomputa solo (no necesita invalidacion manual).
final lastPanelLocationProvider =
    FutureProvider<LastPanelLocation>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const LastPanelLocation();
  }
  final ds = ref.watch(subjectsDataSourceProvider);
  final result = await ds.getLastPanel();
  return LastPanelLocation(
    subjectId: result.subjectId,
    nodeId: result.nodeId,
  );
});
