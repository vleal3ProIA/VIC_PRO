/// Rol de un usuario dentro de un tenant. La granularidad por permisos
/// individuales vendrá en M2 RBAC (Bloque 2). Por ahora estos 3 roles
/// son suficientes para todas las decisiones de UI/autorización.
enum TenantRole {
  owner,
  admin,
  member;

  /// Parser tolerante: si la BD devuelve un valor inesperado (ej. tras una
  /// migración futura que añada roles), defaulteamos a `member` en vez de
  /// crashear.
  static TenantRole fromString(String value) {
    return switch (value) {
      'owner' => TenantRole.owner,
      'admin' => TenantRole.admin,
      _ => TenantRole.member,
    };
  }

  String toDbString() => name;

  /// True si este rol puede invitar miembros, cambiar roles, eliminar
  /// miembros (excepto al owner) y editar la configuración del tenant.
  bool get isAdmin => this == TenantRole.owner || this == TenantRole.admin;

  /// True si este rol controla la facturación, puede transferir ownership
  /// y borrar el tenant.
  bool get isOwner => this == TenantRole.owner;
}

/// Pertenencia de un usuario a un tenant.
class TenantMember {
  const TenantMember({
    required this.tenantId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  factory TenantMember.fromMap(Map<String, dynamic> map) {
    return TenantMember(
      tenantId: map['tenant_id'] as String,
      userId: map['user_id'] as String,
      role: TenantRole.fromString(map['role'] as String),
      joinedAt: DateTime.parse(map['joined_at'] as String),
    );
  }

  final String tenantId;
  final String userId;
  final TenantRole role;
  final DateTime joinedAt;

  @override
  String toString() => 'TenantMember($userId @ $tenantId, ${role.name})';
}
