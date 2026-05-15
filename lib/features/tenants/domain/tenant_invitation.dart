import 'package:meta/meta.dart';

import 'tenant_member.dart';

/// Invitación pendiente a un tenant. El backend hashea el token; aquí
/// solo manejamos la fila de BD (sin el token plaintext, que solo existe
/// en memoria durante la creación).
@immutable
class TenantInvitation {
  const TenantInvitation({
    required this.id,
    required this.tenantId,
    required this.email,
    required this.role,
    required this.invitedBy,
    required this.expiresAt,
    required this.createdAt,
    this.acceptedAt,
    this.revokedAt,
  });

  factory TenantInvitation.fromMap(Map<String, dynamic> map) {
    return TenantInvitation(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      email: map['email'] as String,
      role: TenantRole.fromString(map['role'] as String),
      invitedBy: map['invited_by'] as String?,
      expiresAt: DateTime.parse(map['expires_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      acceptedAt: map['accepted_at'] == null
          ? null
          : DateTime.parse(map['accepted_at'] as String),
      revokedAt: map['revoked_at'] == null
          ? null
          : DateTime.parse(map['revoked_at'] as String),
    );
  }

  final String id;
  final String tenantId;
  final String email;
  final TenantRole role;
  final String? invitedBy;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;

  /// `true` si la invitación está esperando ser aceptada: no aceptada, no
  /// revocada, no expirada.
  bool get isPending {
    if (acceptedAt != null) return false;
    if (revokedAt != null) return false;
    return expiresAt.isAfter(DateTime.now());
  }

  bool get isExpired =>
      acceptedAt == null && revokedAt == null && !expiresAt.isAfter(DateTime.now());

  @override
  bool operator ==(Object other) => other is TenantInvitation && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Resultado de crear una invitación. Contiene el `token` plaintext que el
/// frontend usa para construir la URL `https://.../invite?token=...` —
/// **solo se muestra UNA vez**. La BD solo guarda su SHA-256 hash.
@immutable
class CreatedInvitation {
  const CreatedInvitation({
    required this.id,
    required this.token,
    required this.expiresAt,
  });

  final String id;
  final String token;
  final DateTime expiresAt;
}
