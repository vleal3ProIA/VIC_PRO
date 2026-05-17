import 'package:meta/meta.dart';

/// Personal Access Token (PAT). Representa un token emitido por el
/// usuario para acceso a la API publica desde scripts/CI sin usar
/// password ni JWT de sesión.
///
/// El campo `secret` SOLO se rellena en la respuesta de creación
/// ([PersonalAccessTokenDataSource.create]) y se muestra una vez en
/// el dialog. Para tokens leídos del listado, [secret] = null y solo
/// se conoce [prefix] (los 12 chars visibles "pat_xxxxxxxx").
@immutable
class PersonalAccessToken {
  const PersonalAccessToken({
    required this.id,
    required this.name,
    required this.prefix,
    required this.scopes,
    required this.createdAt,
    this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
    this.secret,
  });

  factory PersonalAccessToken.fromMap(Map<String, dynamic> m) {
    return PersonalAccessToken(
      id: m['id'] as String,
      name: m['name'] as String,
      prefix: m['prefix'] as String,
      scopes: (m['scopes'] as List?)?.cast<String>() ?? const ['read'],
      createdAt: DateTime.parse(m['created_at'] as String),
      expiresAt: m['expires_at'] != null
          ? DateTime.parse(m['expires_at'] as String)
          : null,
      lastUsedAt: m['last_used_at'] != null
          ? DateTime.parse(m['last_used_at'] as String)
          : null,
      revokedAt: m['revoked_at'] != null
          ? DateTime.parse(m['revoked_at'] as String)
          : null,
      secret: m['token'] as String?,
    );
  }

  final String id;
  final String name;

  /// 12 chars "pat_xxxxxxxx" visibles en cualquier momento. Es lo
  /// único que la UI muestra de un token revocado/listado.
  final String prefix;

  final List<String> scopes;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  /// Raw token (`pat_<prefix>_<base64url-32-bytes>`). SOLO presente
  /// inmediatamente después de crear -- jamás se vuelve a poder leer.
  final String? secret;

  bool get isRevoked => revokedAt != null;
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isActive => !isRevoked && !isExpired;

  /// `true` si el token tiene scope 'write' (puede mutar via API).
  bool get canWrite => scopes.contains('write');
}
