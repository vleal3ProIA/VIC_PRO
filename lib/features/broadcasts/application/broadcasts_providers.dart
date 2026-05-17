import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/broadcasts_datasource.dart';
import '../domain/broadcast.dart';

final broadcastsDataSourceProvider = Provider<BroadcastsDataSource>((ref) {
  return BroadcastsDataSource(ref.watch(supabaseClientProvider));
});

/// Lista completa de broadcasts.
final broadcastsListProvider = FutureProvider<List<Broadcast>>((ref) async {
  return ref.watch(broadcastsDataSourceProvider).list();
});

/// Detalle de un broadcast — `.family` por id. La pantalla de detail
/// lo combina con polling cuando status == 'sending'.
final broadcastDetailProvider =
    FutureProvider.family<Broadcast, String>((ref, id) async {
  return ref.watch(broadcastsDataSourceProvider).get(id);
});
