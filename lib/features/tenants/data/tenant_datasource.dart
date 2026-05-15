import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/tenant.dart';
import '../domain/tenant_member.dart';
import '../domain/tenant_member_profile.dart';

/// Acceso a `public.tenants` y `public.tenant_members`. La RLS limita lo que
/// el cliente puede ver/modificar; este datasource solo proxyifica las
/// llamadas REST, no aplica autorización extra.
class TenantDataSource {
  const TenantDataSource(this._client);

  final SupabaseClient _client;

  /// Lista los tenants donde el usuario actual es miembro (RLS lo asegura).
  /// Ordenados con el personal al final para que el primero sea siempre
  /// un tenant "real" si lo hay.
  Future<List<Tenant>> listMyTenants() async {
    final data = await _client
        .from('tenants')
        .select()
        .order('is_personal') // false primero, true al final
        .order('created_at');
    return (data as List)
        .map((row) => Tenant.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Lista los miembros de un tenant (RLS impide ver miembros de tenants
  /// ajenos). Devuelve solo IDs + role; para enriquecer con perfil + email
  /// usa [listMembersWithProfile].
  Future<List<TenantMember>> listMembers(String tenantId) async {
    final data = await _client
        .from('tenant_members')
        .select()
        .eq('tenant_id', tenantId)
        .order('joined_at');
    return (data as List)
        .map((row) => TenantMember.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Lista los miembros de un tenant con info de perfil (display_name,
  /// avatar) y email — vía la RPC `list_tenant_members_with_profile`, que
  /// es SECURITY DEFINER y filtra internamente a tenants donde el caller
  /// es miembro.
  Future<List<TenantMemberProfile>> listMembersWithProfile(
    String tenantId,
  ) async {
    final data = await _client.rpc<List<dynamic>>(
      'list_tenant_members_with_profile',
      params: {'p_tenant_id': tenantId},
    );
    return data
        .map(
          (row) => TenantMemberProfile.fromMap(row as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  /// Crea un nuevo tenant (no-personal) cuyo owner será el usuario actual.
  /// El cliente debe pasar `slug` único; si colisiona, Postgres devuelve
  /// 23505 (lo dejamos burbujear como excepción).
  Future<Tenant> create({
    required String name,
    required String slug,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot create tenant: not authenticated');
    }
    // Inserción + lectura en una sola RPC para ahorrar viaje.
    final inserted = await _client
        .from('tenants')
        .insert({
          'name': name,
          'slug': slug,
          'owner_id': userId,
          'is_personal': false,
        })
        .select()
        .single();
    // El trigger `on_tenant_created_membership` (migration 0009) inserta
    // automáticamente la fila en `tenant_members` con role='owner' para el
    // owner_id. No tenemos que hacer ese segundo INSERT aquí.
    return Tenant.fromMap(inserted);
  }

  /// Actualiza el nombre de un tenant. Requiere ser admin (RLS lo asegura).
  Future<void> rename({required String tenantId, required String name}) async {
    await _client.from('tenants').update({'name': name}).eq('id', tenantId);
  }

  /// Salir voluntariamente de un tenant. RLS impide salirte del personal o
  /// si eres el owner.
  Future<void> leave(String tenantId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('tenant_members')
        .delete()
        .eq('tenant_id', tenantId)
        .eq('user_id', userId);
  }

  /// Echa a un miembro del tenant. La RLS exige que el caller sea admin.
  /// No se puede usar para echar al owner; la RLS lo rechazaría también.
  Future<void> removeMember({
    required String tenantId,
    required String userId,
  }) async {
    await _client
        .from('tenant_members')
        .delete()
        .eq('tenant_id', tenantId)
        .eq('user_id', userId);
  }
}
