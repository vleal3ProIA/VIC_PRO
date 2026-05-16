import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/stripe_branding.dart';

/// Acceso admin al branding de la propia cuenta Stripe de la plataforma.
/// Todas las operaciones pasan por la Edge Function
/// `admin-stripe-branding`, que valida JWT + rol admin + rate limit.
class AdminStripeBrandingDataSource {
  const AdminStripeBrandingDataSource(this._client);

  final SupabaseClient _client;

  /// Devuelve el branding + business_profile actuales.
  Future<StripeBranding> get() async {
    final res = await _client.functions.invoke(
      'admin-stripe-branding',
      body: {'action': 'get'},
    );
    final payload = res.data as Map<String, dynamic>?;
    if (payload == null) {
      throw const StripeBrandingException('empty_response');
    }
    if (payload['error'] != null) {
      throw StripeBrandingException(
        payload['error'] as String,
        detail: payload['detail'] as String?,
      );
    }
    return StripeBranding.fromPayload(payload);
  }

  /// Patch a `settings.branding.{primary_color,secondary_color}`. Cualquier
  /// campo null se omite del patch.
  Future<void> updateBranding({
    String? primaryColor,
    String? secondaryColor,
  }) async {
    final res = await _client.functions.invoke(
      'admin-stripe-branding',
      body: {
        'action': 'update_branding',
        if (primaryColor != null) 'primary_color': primaryColor,
        if (secondaryColor != null) 'secondary_color': secondaryColor,
      },
    );
    final payload = res.data as Map<String, dynamic>?;
    if (payload == null) {
      throw const StripeBrandingException('empty_response');
    }
    if (payload['error'] != null) {
      throw StripeBrandingException(
        payload['error'] as String,
        detail: payload['detail'] as String?,
      );
    }
  }

  /// Patch a `business_profile.*`. Cualquier campo null se omite.
  Future<void> updateBusiness({
    String? name,
    String? supportEmail,
    String? url,
    String? supportPhone,
    StripeSupportAddress? supportAddress,
  }) async {
    final addrMap = supportAddress?.toUpdateMap();
    final res = await _client.functions.invoke(
      'admin-stripe-branding',
      body: {
        'action': 'update_business',
        if (name != null) 'name': name,
        if (supportEmail != null) 'support_email': supportEmail,
        if (url != null) 'url': url,
        if (supportPhone != null) 'support_phone': supportPhone,
        if (addrMap != null && addrMap.isNotEmpty) 'support_address': addrMap,
      },
    );
    final payload = res.data as Map<String, dynamic>?;
    if (payload == null) {
      throw const StripeBrandingException('empty_response');
    }
    if (payload['error'] != null) {
      throw StripeBrandingException(
        payload['error'] as String,
        detail: payload['detail'] as String?,
      );
    }
  }

  /// Sube el logo (image/png|jpeg|gif|webp, máx 4MB) a Stripe Files y lo
  /// asocia a `settings.branding.logo`. Devuelve `{logoFileId, logoUrl?}`.
  Future<({String logoFileId, String? logoUrl})> uploadLogo({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final res = await _client.functions.invoke(
      'admin-stripe-branding',
      body: {
        'action': 'upload_logo',
        'filename': filename,
        'mime_type': mimeType,
        'data_base64': base64Encode(bytes),
      },
    );
    final payload = res.data as Map<String, dynamic>?;
    if (payload == null) {
      throw const StripeBrandingException('empty_response');
    }
    if (payload['error'] != null) {
      throw StripeBrandingException(
        payload['error'] as String,
        detail: payload['detail'] as String?,
      );
    }
    return (
      logoFileId: payload['logo_file_id'] as String,
      logoUrl: payload['logo_url'] as String?,
    );
  }
}

class StripeBrandingException implements Exception {
  const StripeBrandingException(this.code, {this.detail});

  /// Código corto de error de la Edge Function (`stripe_error`,
  /// `invalid_color`, `rate_limited`, etc.).
  final String code;

  /// Mensaje detallado de Stripe (solo cuando `code == 'stripe_error'`).
  /// Útil para diagnosticar campos rechazados (URL inválida, teléfono mal
  /// formateado, file demasiado grande detectado por Stripe, etc.).
  final String? detail;

  @override
  String toString() =>
      detail == null ? 'StripeBrandingException($code)' : 'StripeBrandingException($code: $detail)';
}
