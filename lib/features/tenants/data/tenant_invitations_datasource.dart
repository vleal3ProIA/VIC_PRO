import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/tenant_invitation.dart';
import '../domain/tenant_member.dart';

/// Acceso a `public.tenant_invitations` (vía SELECT con RLS) y a la Edge
/// Function `tenant-invitations` (para create / accept / revoke, que
/// necesitan service-role para tareas cross-tenant).
class TenantInvitationsDataSource {
  const TenantInvitationsDataSource(this._client);

  final SupabaseClient _client;
  static const _functionName = 'tenant-invitations';

  /// Lista invitaciones de un tenant — RLS deja ver solo las del tenant
  /// donde eres admin/owner.
  Future<List<TenantInvitation>> listForTenant(String tenantId) async {
    final data = await _client
        .from('tenant_invitations')
        .select()
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((row) => TenantInvitation.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Crea una invitación. Devuelve el token plaintext (solo visible una vez).
  Future<CreatedInvitation> create({
    required String tenantId,
    required String email,
    required TenantRole role,
    int expiresDays = 7,
  }) async {
    final response = await _client.functions.invoke(
      _functionName,
      body: {
        'action': 'create',
        'tenant_id': tenantId,
        'email': email.trim().toLowerCase(),
        'role': role.toDbString(),
        'expires_days': expiresDays,
      },
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) {
      throw const TenantInvitationException('empty_response');
    }
    if (payload['error'] != null) {
      throw TenantInvitationException(payload['error'] as String);
    }
    return CreatedInvitation(
      id: payload['invitation_id'] as String,
      token: payload['token'] as String,
      expiresAt: DateTime.parse(payload['expires_at'] as String),
    );
  }

  /// Acepta una invitación con el token plaintext recibido en el email/URL.
  /// El backend verifica + crea la membership. Devuelve `(tenant_id, role)`.
  Future<({String tenantId, TenantRole role})> accept(String token) async {
    final response = await _client.functions.invoke(
      _functionName,
      body: {'action': 'accept', 'token': token},
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) {
      throw const TenantInvitationException('empty_response');
    }
    if (payload['error'] != null) {
      throw TenantInvitationException(payload['error'] as String);
    }
    return (
      tenantId: payload['tenant_id'] as String,
      role: TenantRole.fromString(payload['role'] as String),
    );
  }

  /// Revoca una invitación pendiente. Solo admin del tenant emisor.
  Future<void> revoke(String invitationId) async {
    final response = await _client.functions.invoke(
      _functionName,
      body: {'action': 'revoke', 'invitation_id': invitationId},
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload?['error'] != null) {
      throw TenantInvitationException(payload!['error'] as String);
    }
  }
}

/// Excepción con el código de error que devuelve la Edge Function. La UI
/// mapea estos códigos a mensajes localizados.
class TenantInvitationException implements Exception {
  const TenantInvitationException(this.code);
  final String code;

  @override
  String toString() => 'TenantInvitationException($code)';
}
