import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/deleted_tenant.dart';

/// Lee y opera sobre la "papelera" de tenants soft-borrados.
/// Todas las llamadas son RPCs SECURITY DEFINER que internamente
/// comprueban `public.is_admin()` — usuarios sin rol admin reciben 0
/// filas en `list` y `not_authorized` en `restore`/`softDelete`.
class AdminTrashDataSource {
  const AdminTrashDataSource(this._client);

  final SupabaseClient _client;

  Future<List<DeletedTenant>> listDeletedTenants() async {
    final data = await _client.rpc<dynamic>('list_deleted_tenants');
    final rows = (data as List?) ?? const [];
    return rows
        .cast<Map<String, dynamic>>()
        .map(DeletedTenant.fromMap)
        .toList(growable: false);
  }

  /// Soft-borra un tenant. Solo admin global o owner. La RPC también
  /// hace cascade lógico sobre `tenant_members`.
  Future<void> softDeleteTenant(String tenantId) async {
    await _client.rpc<void>(
      'soft_delete_tenant',
      params: {'p_tenant_id': tenantId},
    );
  }

  /// Restaura un tenant + sus miembros. Solo admin global.
  Future<void> restoreTenant(String tenantId) async {
    await _client.rpc<void>(
      'restore_tenant',
      params: {'p_tenant_id': tenantId},
    );
  }
}
