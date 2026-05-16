import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/admin_trash_datasource.dart';
import '../domain/deleted_tenant.dart';

final adminTrashDataSourceProvider = Provider<AdminTrashDataSource>((ref) {
  return AdminTrashDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de tenants borrados que ve el admin. Se invalida tras
/// soft_delete/restore desde la pantalla para refrescar.
final deletedTenantsProvider = FutureProvider<List<DeletedTenant>>((ref) async {
  final ds = ref.watch(adminTrashDataSourceProvider);
  return ds.listDeletedTenants();
});
