import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import 'reauth_datasource.dart';

/// DataSource para re-autenticacion con password. Inyectable en
/// pantallas/widgets que necesiten validar la identidad del user antes
/// de una accion critica (delete-account, create-pat con scope write,
/// etc.).
final reauthDataSourceProvider = Provider<ReauthDataSource>((ref) {
  return ReauthDataSource(ref.watch(supabaseClientProvider));
});
