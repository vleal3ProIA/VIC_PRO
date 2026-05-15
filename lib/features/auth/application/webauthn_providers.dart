import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/auth/data/datasources/webauthn_supabase_datasource.dart';
import 'package:myapp/features/auth/data/repositories/webauthn_repository_impl.dart';
import 'package:myapp/features/auth/domain/entities/passkey_credential.dart';
import 'package:myapp/features/auth/domain/repositories/webauthn_repository.dart';

final webauthnDataSourceProvider =
    Provider<WebauthnSupabaseDataSource>((ref) {
  return WebauthnSupabaseDataSource(ref.watch(supabaseClientProvider));
});

final webauthnRepositoryProvider = Provider<WebauthnRepository>((ref) {
  return WebauthnRepositoryImpl(
    dataSource: ref.watch(webauthnDataSourceProvider),
  );
});

/// Lista de passkeys del usuario actual. `null` o error → lista vacía.
/// Se recalcula al cambiar la autenticación (login/logout).
final myPasskeysProvider = FutureProvider<List<PasskeyCredential>>((ref) async {
  final authed = ref.watch(isAuthenticatedProvider);
  if (!authed) return const [];
  final result = await ref.watch(webauthnRepositoryProvider).listPasskeys();
  return result.fold((_) => const [], (list) => list);
});
