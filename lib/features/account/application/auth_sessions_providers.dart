import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/auth_sessions_datasource.dart';
import '../domain/auth_session.dart';

final authSessionsDataSourceProvider = Provider<AuthSessionsDataSource>((ref) {
  return AuthSessionsDataSource(ref.watch(supabaseClientProvider));
});

final authSessionsProvider = FutureProvider<List<AuthSession>>((ref) async {
  final ds = ref.watch(authSessionsDataSourceProvider);
  return ds.list();
});
