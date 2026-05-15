/// Item simple para listar los passkeys registrados de un usuario. Mapea
/// una fila de `public.webauthn_credentials` (sin exponer la public key).
class PasskeyCredential {
  const PasskeyCredential({
    required this.id,
    required this.credentialId,
    required this.createdAt,
    this.friendlyName,
    this.deviceType,
    this.backedUp,
    this.lastUsedAt,
  });

  factory PasskeyCredential.fromMap(Map<String, dynamic> map) {
    return PasskeyCredential(
      id: map['id'] as String,
      credentialId: map['credential_id'] as String,
      friendlyName: map['friendly_name'] as String?,
      deviceType: map['device_type'] as String?,
      backedUp: map['backed_up'] as bool?,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastUsedAt: map['last_used_at'] == null
          ? null
          : DateTime.parse(map['last_used_at'] as String),
    );
  }

  final String id;
  final String credentialId;
  final String? friendlyName;
  final String? deviceType;
  final bool? backedUp;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}
