// ============================================================================
// Admin ACL · DataSource (PR-Super-A2)
// ----------------------------------------------------------------------------
// Acceso a las 5 RPCs `super_admin_*` creadas en la migracion 0044:
//
//   super_admin_list_admins()                  -> List<AdminRow>
//   super_admin_promote_to_admin(uuid)         -> void
//   super_admin_revoke_admin(uuid)             -> void
//   super_admin_grant_capability(uuid, text)   -> void
//   super_admin_revoke_capability(uuid, text)  -> void
//
// Todas validan `is_super_admin()` server-side -- si el caller no es
// super, lanzan `super admin only` (PostgrestException). El cliente lo
// recibe como excepcion y la UI lo muestra. Defensa en profundidad:
// **NUNCA** confiamos en que la UI haya bloqueado el acceso; el
// servidor SIEMPRE re-valida.
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/admin_row.dart';

class AdminAclDataSource {
  const AdminAclDataSource(this._client);

  final SupabaseClient _client;

  /// Lista todos los admins (incluido el super) + sus capabilities.
  /// Solo super puede llamarla. Devuelve filas ordenadas: super
  /// primero, luego admins por email asc.
  Future<List<AdminRow>> listAdmins() async {
    final data = await _client.rpc<dynamic>('super_admin_list_admins');
    if (data is! List) {
      throw const AdminAclException('invalid_response');
    }
    return data
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => AdminRow.fromMap(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Promueve a un user (uuid) a admin. NO le asigna capabilities --
  /// el super debe llamar `grantCapability` despues por cada una.
  Future<void> promoteToAdmin(String userId) async {
    await _client.rpc<dynamic>(
      'super_admin_promote_to_admin',
      params: {'p_user_id': userId},
    );
  }

  /// Promueve por email (UX: el super conoce el email, no el UUID).
  /// Resuelve el email -> user_id server-side y delega en
  /// `super_admin_promote_to_admin`. Throws `AdminAclException` con
  /// codigo estandarizado segun el error de la RPC (migracion 0045):
  ///
  ///   `user_not_found`  -> P0002 (email no existe en auth.users)
  ///   `already_admin`   -> P0003 (el user ya es admin)
  ///   `super_only`      -> P0001 (caller no es super)
  ///
  /// Devuelve el user_id promovido (util para invalidar caches).
  Future<String> promoteToAdminByEmail(String email) async {
    try {
      final data = await _client.rpc<dynamic>(
        'super_admin_promote_to_admin_by_email',
        params: {'p_email': email},
      );
      // La RPC devuelve un UUID escalar (no array). Supabase lo serializa
      // como String JSON.
      if (data is String && data.isNotEmpty) return data;
      throw const AdminAclException('invalid_response');
    } on PostgrestException catch (e) {
      // Mapeo de SQLSTATE -> codigo de error de la app.
      final msg = e.message.toLowerCase();
      if (msg.contains('user not found')) {
        throw const AdminAclException('user_not_found');
      }
      if (msg.contains('already admin')) {
        throw const AdminAclException('already_admin');
      }
      if (msg.contains('super admin only')) {
        throw const AdminAclException('super_only');
      }
      if (msg.contains('email required')) {
        throw const AdminAclException('email_required');
      }
      rethrow;
    }
  }

  /// Revoca rol admin. Borra todas las capabilities del user en
  /// cascada. NO se puede aplicar al super (la RPC lanza).
  Future<void> revokeAdmin(String userId) async {
    try {
      await _client.rpc<dynamic>(
        'super_admin_revoke_admin',
        params: {'p_user_id': userId},
      );
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('cannot revoke super admin')) {
        throw const AdminAclException('cannot_revoke_super');
      }
      if (msg.contains('super admin only')) {
        throw const AdminAclException('super_only');
      }
      rethrow;
    }
  }

  /// Otorga una capability concreta a un admin. Idempotente
  /// (ON CONFLICT DO NOTHING).
  Future<void> grantCapability({
    required String userId,
    required String capability,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'super_admin_grant_capability',
        params: {'p_user_id': userId, 'p_capability': capability},
      );
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('target_not_admin')) {
        throw const AdminAclException('target_not_admin');
      }
      if (msg.contains('super admin only')) {
        throw const AdminAclException('super_only');
      }
      rethrow;
    }
  }

  /// Revoca una capability. Idempotente.
  Future<void> revokeCapability({
    required String userId,
    required String capability,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'super_admin_revoke_capability',
        params: {'p_user_id': userId, 'p_capability': capability},
      );
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('super admin only')) {
        throw const AdminAclException('super_only');
      }
      rethrow;
    }
  }
}

class AdminAclException implements Exception {
  const AdminAclException(this.code);
  final String code;
  @override
  String toString() => 'AdminAclException($code)';
}
