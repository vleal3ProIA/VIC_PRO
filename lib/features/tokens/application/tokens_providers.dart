import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/tokens_datasource.dart';
import '../domain/personal_access_token.dart';

final tokensDataSourceProvider = Provider<TokensDataSource>((ref) {
  return TokensDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de PATs del usuario actual. Se invalida tras create/revoke.
final userTokensProvider = FutureProvider<List<PersonalAccessToken>>((
  ref,
) async {
  final ds = ref.watch(tokensDataSourceProvider);
  return ds.list();
});
