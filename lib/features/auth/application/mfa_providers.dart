import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';

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
