import 'package:meta/meta.dart';

import 'tenant_member.dart';

/// `TenantMember` enriquecido con la información de display del profile y
/// el email de auth.users. Se obtiene vía la RPC
/// `list_tenant_members_with_profile`, no construyendo `TenantMember + Profile`
/// por separado.
@immutable
class TenantMemberProfile {
  const TenantMemberProfile({
    required this.tenantId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.email,
  });

  factory TenantMemberProfile.fromMap(Map<String, dynamic> map) {
    return TenantMemberProfile(
      tenantId: map['tenant_id'] as String,
      userId: map['user_id'] as String,
      role: TenantRole.fromString(map['role'] as String),
      joinedAt: DateTime.parse(map['joined_at'] as String),
      username: map['username'] as String?,
      displayName: map['display_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      email: map['email'] as String?,
    );
  }

  final String tenantId;
  final String userId;
  final TenantRole role;
  final DateTime joinedAt;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? email;

  /// Mejor nombre disponible: display_name > username > email > "User …".
  String displayLabel() {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    if (username != null && username!.isNotEmpty) return username!;
    if (email != null && email!.isNotEmpty) return email!;
    return 'User ${userId.substring(0, 8)}';
  }

  /// 1-2 caracteres para mostrar como avatar fallback.
  String initials() {
    final src = displayLabel();
    final parts = src.split(RegExp(r'\s+|@')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}
