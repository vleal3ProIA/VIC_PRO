import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cliente raíz de Supabase. Inicializado en main() vía `Supabase.initialize`.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Stream reactivo del estado de sesión. La UI escucha esto para saber si
/// hay usuario autenticado.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// Sesión actual (o null). Sincrónico, basado en el último evento del stream.
///
/// Toma la sesión del propio evento de `onAuthStateChange` cuando está
/// disponible (es lo que dispara el cambio) y solo cae al getter
/// `currentSession` como respaldo (p. ej. antes del primer evento). Así el
/// guard del router ve la sesión nueva en el mismo ciclo en que el stream
/// emite, sin depender de que el getter ya esté actualizado.
final currentSessionProvider = Provider<Session?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  final client = ref.watch(supabaseClientProvider);
  return authState.valueOrNull?.session ?? client.auth.currentSession;
});

/// Usuario actual (o null). Derivado de la sesión.
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(currentSessionProvider)?.user;
});

/// `true` si hay usuario autenticado. Útil para guards del router.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentSessionProvider) != null;
});
