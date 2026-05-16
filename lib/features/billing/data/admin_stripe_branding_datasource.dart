import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/stripe_branding.dart';

/// Acceso admin al branding de la propia cuenta Stripe — **solo lectura**.
///
/// Stripe rechaza con 403 cualquier `POST /v1/account` sobre la propia
/// cuenta de plataforma. Los settings (logo, colores, business_profile)
/// solo se pueden editar desde `https://dashboard.stripe.com/settings/...`.
/// Por eso este datasource expone únicamente `get()`; la UI muestra un
/// botón "Editar en Stripe Dashboard" que abre la pestaña correcta.
class AdminStripeBrandingDataSource {
  const AdminStripeBrandingDataSource(this._client);

  final SupabaseClient _client;

  /// Devuelve el branding + business_profile actuales.
  Future<StripeBranding> get() async {
    try {
      final res = await _client.functions.invoke(
        'admin-stripe-branding',
        body: {'action': 'get'},
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
      return StripeBranding.fromPayload(payload);
    } on FunctionException catch (e) {
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
  /// `rate_limited`, `not_admin`, etc.).
  final String code;

  /// Mensaje detallado de Stripe cuando aplica.
  final String? detail;

  @override
  String toString() => detail == null
      ? 'StripeBrandingException($code)'
      : 'StripeBrandingException($code: $detail)';
}
