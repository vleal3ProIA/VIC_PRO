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
    final payload = await _invoke({'action': 'get'});
    return StripeBranding.fromPayload(payload);
  }

  /// Patch a `settings.branding.{primary_color,secondary_color}`. Cualquier
  /// campo null se omite del patch.
  Future<void> updateBranding({
    String? primaryColor,
    String? secondaryColor,
  }) async {
    await _invoke({
      'action': 'update_branding',
      if (primaryColor != null) 'primary_color': primaryColor,
      if (secondaryColor != null) 'secondary_color': secondaryColor,
    });
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
    await _invoke({
      'action': 'update_business',
      if (name != null) 'name': name,
      if (supportEmail != null) 'support_email': supportEmail,
      if (url != null) 'url': url,
      if (supportPhone != null) 'support_phone': supportPhone,
      if (addrMap != null && addrMap.isNotEmpty) 'support_address': addrMap,
    });
  }

  /// Sube el logo (image/png|jpeg|gif|webp, máx 4MB) a Stripe Files y lo
  /// asocia a `settings.branding.logo`. Devuelve `{logoFileId, logoUrl?}`.
  Future<({String logoFileId, String? logoUrl})> uploadLogo({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final payload = await _invoke({
      'action': 'upload_logo',
      'filename': filename,
      'mime_type': mimeType,
      'data_base64': base64Encode(bytes),
    });
    return (
      logoFileId: payload['logo_file_id'] as String,
      logoUrl: payload['logo_url'] as String?,
    );
  }

  /// Wrapper común para todas las llamadas a la Edge Function. Convierte
  /// cualquier fallo (HTTP 4xx/5xx, body no parseable, body con
  /// `{error,detail}`) en una `StripeBrandingException` con el código y
  /// (cuando existe) el `detail` literal de Stripe — así la UI puede
  /// mostrarle al admin exactamente qué rechaza Stripe en vez de un
  /// "no se pudo guardar" opaco.
  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(
        'admin-stripe-branding',
        body: body,
      );
      final data = res.data;
      if (data is! Map) {
        throw const StripeBrandingException('empty_response');
      }
      final payload = data.cast<String, dynamic>();
      if (payload['error'] != null) {
        throw StripeBrandingException(
          payload['error'] as String,
          detail: payload['detail'] as String?,
        );
      }
      return payload;
    } on FunctionException catch (e) {
      // Edge Function devolvió 4xx/5xx. supabase_flutter envuelve el body
      // en `e.details` (ya parseado a Map si era JSON).
      final details = e.details;
      if (details is Map) {
        final m = details.cast<String, dynamic>();
        final code = m['error'] as String?;
        if (code != null) {
          throw StripeBrandingException(
            code,
            detail: m['detail'] as String?,
          );
        }
      }
      // No JSON parseable — devolvemos al menos el HTTP status para tener
      // alguna pista.
      throw StripeBrandingException(
        'http_${e.status}',
        detail: details is String ? details : details?.toString(),
      );
    }
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
  String toString() => detail == null
      ? 'StripeBrandingException($code)'
      : 'StripeBrandingException($code: $detail)';
}
