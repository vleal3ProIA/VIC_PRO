import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';

/// `true` cuando el usuario tiene sesión iniciada pero su AAL actual es
/// menor que el requerido (MFA verificado pendiente).
///
/// Depende del stream `authStateChangesProvider` para re-evaluarse cuando
/// cambia el estado de auth (login, MFA verify, logout).
final mfaChallengePendingProvider = Provider<bool>((ref) {
  ref.watch(authStateChangesProvider);
  // currentSession también dispara rebuilds.
  final session = ref.watch(currentSessionProvider);
  if (session == null) return false;
  return ref.watch(authRepositoryProvider).isMfaChallengePending();
});

/// Lista de factores MFA del usuario. `null`/error → lista vacía (la UI lo
/// trata como "sin MFA").
///
/// Observa `isAuthenticatedProvider` (bool) en vez de `currentSessionProvider`
/// para evitar re-fetcharse en cada `tokenRefreshed` — eso, combinado con que
/// cada fetch puede gatillar al SDK a refrescar, provocaba un bucle que
/// terminaba en 429 y la sesión rota.
final mfaFactorsProvider = FutureProvider<List<MfaFactor>>((ref) async {
  final authed = ref.watch(isAuthenticatedProvider);
  if (!authed) return const [];
  final result = await ref.watch(authRepositoryProvider).listMfaFactors();
  return result.fold((_) => const [], (factors) => factors);
});
