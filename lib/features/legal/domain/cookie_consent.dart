/// Estado del consentimiento de cookies / almacenamiento local.
///
/// - **essential** (siempre `true`): cookies/almacenamiento necesarios para
///   que la app funcione (sesión Supabase, idioma, tema, etc.). Sin esto,
///   la app simplemente no opera, así que no es opt-in.
/// - **analytics** (opt-in): integración futura con analítica de terceros
///   (Google Analytics, Plausible…). Por defecto `false`. Hoy la app NO
///   tiene analítica, pero el toggle existe para cuando se añada — el
///   consentimiento debe pedirse ANTES de cargar el script.
///
/// La app guarda el resultado en `SharedPreferences`. Mientras `decidedAt`
/// sea `null`, el banner se muestra.
class CookieConsent {
  const CookieConsent({
    this.analytics = false,
    this.decidedAt,
  });

  /// Versión persistida en `SharedPreferences`. Si en el futuro cambian las
  /// categorías o el texto, basta con bumpear la versión y todos los
  /// usuarios verán el banner otra vez.
  static const int version = 1;

  /// El consentimiento se considera "tomado" cuando el usuario interactúa
  /// con el banner (Acepta / Rechaza / Personaliza).
  final DateTime? decidedAt;

  /// `true` si el usuario optó por permitir analítica opcional.
  final bool analytics;

  /// `essential` siempre es `true` — la app no funciona sin sesión, idioma,
  /// tema… No se puede desactivar.
  bool get essential => true;

  bool get isDecided => decidedAt != null;

  CookieConsent copyWith({
    bool? analytics,
    DateTime? decidedAt,
  }) {
    return CookieConsent(
      analytics: analytics ?? this.analytics,
      decidedAt: decidedAt ?? this.decidedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'analytics': analytics,
        'decidedAt': decidedAt?.toIso8601String(),
      };

  static CookieConsent? fromJson(Map<String, dynamic> json) {
    final v = json['version'];
    if (v != version) return null; // versión antigua → re-preguntar
    return CookieConsent(
      analytics: (json['analytics'] as bool?) ?? false,
      decidedAt: json['decidedAt'] is String
          ? DateTime.tryParse(json['decidedAt'] as String)
          : null,
    );
  }
}
