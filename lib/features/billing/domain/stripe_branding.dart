import 'package:meta/meta.dart';

/// Representa la configuración de branding + business profile de la propia
/// cuenta Stripe de la plataforma. Es lo que aparece en las facturas PDF y
/// en las páginas hospedadas (Checkout, Customer Portal, invoice pages):
/// logo + colores + nombre comercial + soporte + dirección fiscal.
///
/// Se hidrata desde la respuesta de la Edge Function
/// `admin-stripe-branding` (acción `get`):
///
/// ```json
/// {
///   "branding": {
///     "primary_color": "#1F2937",
///     "secondary_color": "#6366F1",
///     "logo": "file_1ABc...",
///     "logo_url": "https://files.stripe.com/links/...",
///     "icon": null
///   },
///   "business_profile": {
///     "name": "Acme SL",
///     "support_email": "soporte@acme.com",
///     "url": "https://acme.com",
///     "support_phone": "+34 600 000 000",
///     "support_address": {
///       "line1": "C/ Mayor 1",
///       "city": "Madrid",
///       "postal_code": "28013",
///       "country": "ES"
///     }
///   }
/// }
/// ```
@immutable
class StripeBranding {
  const StripeBranding({
    required this.primaryColor,
    required this.secondaryColor,
    required this.logoFileId,
    required this.logoUrl,
    required this.iconFileId,
    required this.businessName,
    required this.supportEmail,
    required this.url,
    required this.supportPhone,
    required this.supportAddress,
  });

  factory StripeBranding.fromPayload(Map<String, dynamic> payload) {
    final branding = (payload['branding'] as Map?)?.cast<String, dynamic>() ?? const {};
    final profile = (payload['business_profile'] as Map?)?.cast<String, dynamic>() ?? const {};
    final addr = (profile['support_address'] as Map?)?.cast<String, dynamic>() ?? const {};
    return StripeBranding(
      primaryColor: branding['primary_color'] as String?,
      secondaryColor: branding['secondary_color'] as String?,
      logoFileId: branding['logo'] as String?,
      logoUrl: branding['logo_url'] as String?,
      iconFileId: branding['icon'] as String?,
      businessName: profile['name'] as String?,
      supportEmail: profile['support_email'] as String?,
      url: profile['url'] as String?,
      supportPhone: profile['support_phone'] as String?,
      supportAddress: StripeSupportAddress.fromMap(addr),
    );
  }

  /// Vacío — default mientras se carga.
  static const empty = StripeBranding(
    primaryColor: null,
    secondaryColor: null,
    logoFileId: null,
    logoUrl: null,
    iconFileId: null,
    businessName: null,
    supportEmail: null,
    url: null,
    supportPhone: null,
    supportAddress: StripeSupportAddress.empty,
  );

  /// Hex `#RRGGBB` o null si nunca se ha fijado.
  final String? primaryColor;
  final String? secondaryColor;

  /// `file_xxx` de Stripe Files API.
  final String? logoFileId;

  /// URL pública (fileLinks.create) — opcional, solo para preview en UI.
  final String? logoUrl;

  final String? iconFileId;

  // business_profile.*
  final String? businessName;
  final String? supportEmail;
  final String? url;
  final String? supportPhone;
  final StripeSupportAddress supportAddress;

  StripeBranding copyWith({
    String? primaryColor,
    String? secondaryColor,
    String? logoFileId,
    String? logoUrl,
    String? iconFileId,
    String? businessName,
    String? supportEmail,
    String? url,
    String? supportPhone,
    StripeSupportAddress? supportAddress,
  }) {
    return StripeBranding(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      logoFileId: logoFileId ?? this.logoFileId,
      logoUrl: logoUrl ?? this.logoUrl,
      iconFileId: iconFileId ?? this.iconFileId,
      businessName: businessName ?? this.businessName,
      supportEmail: supportEmail ?? this.supportEmail,
      url: url ?? this.url,
      supportPhone: supportPhone ?? this.supportPhone,
      supportAddress: supportAddress ?? this.supportAddress,
    );
  }
}

@immutable
class StripeSupportAddress {
  const StripeSupportAddress({
    required this.line1,
    required this.line2,
    required this.city,
    required this.postalCode,
    required this.state,
    required this.country,
  });

  factory StripeSupportAddress.fromMap(Map<String, dynamic> m) {
    return StripeSupportAddress(
      line1: m['line1'] as String?,
      line2: m['line2'] as String?,
      city: m['city'] as String?,
      postalCode: m['postal_code'] as String?,
      state: m['state'] as String?,
      country: m['country'] as String?,
    );
  }

  static const empty = StripeSupportAddress(
    line1: null,
    line2: null,
    city: null,
    postalCode: null,
    state: null,
    country: null,
  );

  final String? line1;
  final String? line2;
  final String? city;
  final String? postalCode;
  final String? state;

  /// ISO 3166-1 alpha-2 ("ES", "FR", "DE"...).
  final String? country;

  /// Serializa solo los campos no-null para enviar como patch a Stripe.
  Map<String, String> toUpdateMap() {
    final m = <String, String>{};
    final l1 = line1?.trim();
    final l2 = line2?.trim();
    final c = city?.trim();
    final pc = postalCode?.trim();
    final st = state?.trim();
    final ct = country?.trim();
    if (l1 != null && l1.isNotEmpty) m['line1'] = l1;
    if (l2 != null && l2.isNotEmpty) m['line2'] = l2;
    if (c != null && c.isNotEmpty) m['city'] = c;
    if (pc != null && pc.isNotEmpty) m['postal_code'] = pc;
    if (st != null && st.isNotEmpty) m['state'] = st;
    if (ct != null && ct.isNotEmpty) m['country'] = ct;
    return m;
  }

  bool get isEmpty =>
      (line1?.trim().isEmpty ?? true) &&
      (line2?.trim().isEmpty ?? true) &&
      (city?.trim().isEmpty ?? true) &&
      (postalCode?.trim().isEmpty ?? true) &&
      (state?.trim().isEmpty ?? true) &&
      (country?.trim().isEmpty ?? true);

  StripeSupportAddress copyWith({
    String? line1,
    String? line2,
    String? city,
    String? postalCode,
    String? state,
    String? country,
  }) {
    return StripeSupportAddress(
      line1: line1 ?? this.line1,
      line2: line2 ?? this.line2,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      state: state ?? this.state,
      country: country ?? this.country,
    );
  }
}
