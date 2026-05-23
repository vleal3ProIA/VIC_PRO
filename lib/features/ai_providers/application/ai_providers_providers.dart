// ============================================================================
// AI providers · Providers Riverpod (Fase 0)
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/ai_admin_datasource.dart';

final aiAdminDataSourceProvider = Provider<AiAdminDataSource>((ref) {
  return AiAdminDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de proveedores + credenciales (vía Edge Function ai-admin).
final aiAdminListProvider = FutureProvider<AiAdminData>((ref) {
  return ref.watch(aiAdminDataSourceProvider).list();
});
