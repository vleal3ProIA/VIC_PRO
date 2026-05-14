import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/account/data/datasources/profile_supabase_datasource.dart';
import 'package:myapp/features/account/data/repositories/profile_repository_impl.dart';
import 'package:myapp/features/account/domain/entities/profile.dart';
import 'package:myapp/features/account/domain/repositories/profile_repository.dart';

final profileDataSourceProvider = Provider<ProfileSupabaseDataSource>((ref) {
  return ProfileSupabaseDataSource(ref.watch(supabaseClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepositoryImpl(
    dataSource: ref.watch(profileDataSourceProvider),
  );
});

/// Carga el perfil del usuario autenticado. Se recalcula cuando cambia la
/// sesión (login/logout). Devuelve `null` si no hay sesión.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  final result = await ref.watch(profileRepositoryProvider).getMyProfile();
  return result.fold((_) => null, (profile) => profile);
});
