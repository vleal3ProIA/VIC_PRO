import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/changelog_datasource.dart';
import '../domain/changelog_entry.dart';

final changelogDataSourceProvider = Provider<ChangelogDataSource>((ref) {
  return ChangelogDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de entradas del changelog visibles para el user actual.
/// Para users normales: solo publicadas. Para admins: incluye borradores.
final changelogEntriesProvider = FutureProvider<List<ChangelogEntry>>((
  ref,
) async {
  final ds = ref.watch(changelogDataSourceProvider);
  return ds.list();
});

/// `true` si hay entradas publicadas que el user no ha visto todavía.
/// Lo consume el icono "?" del AppBar para pintar el badge rojo.
final hasUnseenChangelogProvider = FutureProvider<bool>((ref) async {
  final ds = ref.watch(changelogDataSourceProvider);
  return ds.hasUnseen();
});
