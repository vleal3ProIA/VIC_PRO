import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';

import '../data/uploads_datasource.dart';
import '../domain/uploaded_file.dart';

final uploadsDataSourceProvider = Provider<UploadsDataSource>((ref) {
  return UploadsDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de uploads del tenant actual. Se invalida tras upload/delete.
final tenantUploadsProvider = FutureProvider<List<UploadedFile>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  final ds = ref.watch(uploadsDataSourceProvider);
  return ds.list(tenantId: tenantId);
});

/// Cuota actual del tenant. Para mostrar barra en `/files`.
final tenantStorageQuotaProvider = FutureProvider<StorageQuota>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) {
    return const StorageQuota(usedBytes: 0, quotaBytes: -1);
  }
  final ds = ref.watch(uploadsDataSourceProvider);
  return ds.quota(tenantId);
});
