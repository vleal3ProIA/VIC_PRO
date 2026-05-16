import 'package:meta/meta.dart';

/// Sesión activa del usuario tal y como la devuelve la Edge Function
/// `account-sessions`. Una sesión es una "cookie larga": un par
/// (dispositivo, navegador) que tiene un refresh_token vigente.
///
/// Los campos `userAgent` e `ip` los rellena Supabase Auth en el momento
/// de crear la sesión (login/signup). Si el cliente no envió UA — caso
/// raro pero posible — el UA queda en `null` y la UI lo etiqueta como
/// "Unknown device".
@immutable
class AuthSession {
  const AuthSession({
    required this.id,
    required this.userAgent,
    required this.ip,
    required this.createdAt,
    required this.updatedAt,
    required this.notAfter,
    required this.aal,
    required this.isCurrent,
  });

  factory AuthSession.fromMap(Map<String, dynamic> m) {
    DateTime? parseTs(Object? raw) {
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    return AuthSession(
      id: m['id'] as String,
      userAgent: m['user_agent'] as String?,
      ip: m['ip'] as String?,
      createdAt: parseTs(m['created_at']) ?? DateTime.now(),
      updatedAt: parseTs(m['updated_at']),
      notAfter: parseTs(m['not_after']),
      aal: m['aal'] as String?,
      isCurrent: m['is_current'] as bool? ?? false,
    );
  }

  final String id;
  final String? userAgent;
  final String? ip;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Cuándo expira la sesión (si está marcada). null = sin expiración
  /// fija; Supabase la mantiene viva mientras el refresh token siga
  /// usándose.
  final DateTime? notAfter;

  /// Authentication Assurance Level: `aal1` = solo password, `aal2` =
  /// MFA verificado. Útil para etiquetar visualmente sesiones MFA.
  final String? aal;

  /// True si esta sesión es la que el usuario está usando AHORA. La UI
  /// marca esta fila como "Esta sesión" y oculta el botón de revocar
  /// (para que no se desloguee accidentalmente desde aquí; existe el
  /// botón global "Cerrar todas las demás" para todo lo otro).
  final bool isCurrent;
}
