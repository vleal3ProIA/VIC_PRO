import 'package:meta/meta.dart';

/// Configuración del DEPLOY: nombre comercial, logo, paleta, flags
/// globales. Singleton en BD (id = true fijo).
///
/// Diseño:
///  - `commercialName` se usa en AppBar, emails, pestaña del navegador.
///  - `logoUrl` puede ser null → la UI cae a un placeholder con la
///    inicial del nombre.
///  - `colorPalette` es un slug que mapea a un preset hardcoded
///    en `BrandingPalettes` (ver presentation/branding_palettes.dart).
///  - `setupCompleted` controla el redirect a `/setup`.
///  - `registrationEnabled` controla el gate de `/register`.
@immutable
class AppBranding {
  const AppBranding({
    required this.commercialName,
    required this.colorPalette,
    required this.setupCompleted,
    required this.registrationEnabled,
    this.updatedAt,
    this.tagline,
    this.supportEmail,
    this.websiteUrl,
    this.logoUrl,
    this.logoDarkUrl,
    this.faviconUrl,
    this.ogImageUrl,
  });

  factory AppBranding.fromMap(Map<String, dynamic> m) {
    final rawName = (m['commercial_name'] as String?)?.trim() ?? '';
    return AppBranding(
      commercialName: rawName.isEmpty ? 'myapp' : rawName,
      tagline: _emptyToNull(m['tagline'] as String?),
      supportEmail: _emptyToNull(m['support_email'] as String?),
      websiteUrl: _emptyToNull(m['website_url'] as String?),
      logoUrl: _emptyToNull(m['logo_url'] as String?),
      logoDarkUrl: _emptyToNull(m['logo_dark_url'] as String?),
      faviconUrl: _emptyToNull(m['favicon_url'] as String?),
      ogImageUrl: _emptyToNull(m['og_image_url'] as String?),
      colorPalette: (m['color_palette'] as String?) ?? 'blue',
      setupCompleted: m['setup_completed'] as bool? ?? false,
      registrationEnabled: m['registration_enabled'] as bool? ?? false,
      updatedAt: m['updated_at'] != null
          ? DateTime.parse(m['updated_at'] as String)
          : DateTime.now(),
    );
  }

  /// Valor de fallback cuando aún no se ha hidratado desde BD. Sirve
  /// para que la UI no parpadee con string vacíos en el split-segundo
  /// inicial antes de que llegue la primera carga.
  static const fallback = AppBranding(
    commercialName: 'myapp',
    colorPalette: 'blue',
    setupCompleted: false,
    registrationEnabled: false,
    updatedAt: null,
  );

  final String commercialName;
  final String? tagline;
  final String? supportEmail;
  final String? websiteUrl;
  final String? logoUrl;
  final String? logoDarkUrl;
  final String? faviconUrl;
  final String? ogImageUrl;
  final String colorPalette;
  final bool setupCompleted;
  final bool registrationEnabled;
  final DateTime? updatedAt;

  /// `true` si tiene logo configurado para el tema dado.
  bool hasLogoFor({required bool isDark}) {
    if (isDark) {
      return (logoDarkUrl?.isNotEmpty ?? false) ||
          (logoUrl?.isNotEmpty ?? false);
    }
    return logoUrl?.isNotEmpty ?? false;
  }

  /// URL del logo apropiado para el tema actual. Si no hay variante
  /// dark, fallback al light.
  String? logoFor({required bool isDark}) {
    if (isDark && (logoDarkUrl?.isNotEmpty ?? false)) {
      return logoDarkUrl;
    }
    return logoUrl;
  }
}

String? _emptyToNull(String? s) {
  if (s == null) return null;
  final trimmed = s.trim();
  return trimmed.isEmpty ? null : trimmed;
}
