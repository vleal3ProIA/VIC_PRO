import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/promotion_code.dart';

/// Resultado de validar un código en el backend.
sealed class ValidatePromotionCodeResult {
  const ValidatePromotionCodeResult();
}

/// Código aceptado: lleva los datos para mostrar al cliente + pasar al
/// Stripe Checkout.
class PromotionCodeValid extends ValidatePromotionCodeResult {
  const PromotionCodeValid(this.applied);
  final AppliedPromotionCode applied;
}

/// Código rechazado por el backend. `reason` es opaco para evitar
/// enumeración (`not_found_or_expired`, `not_applicable_to_plan`,
/// `not_synced`).
class PromotionCodeInvalid extends ValidatePromotionCodeResult {
  const PromotionCodeInvalid(this.reason);
  final String reason;
}

/// Datasource público (no admin) — solo expone `validate()`. Lo consume
/// el campo "¿Tienes un código promocional?" de `/billing/plans`.
class PromotionCodeValidator {
  const PromotionCodeValidator(this._client);

  final SupabaseClient _client;

  /// Valida un código contra el backend. `planSlug` es opcional: si se
  /// pasa, el backend rechaza con `not_applicable_to_plan` si el cupón
  /// está restringido a otros planes.
  Future<ValidatePromotionCodeResult> validate({
    required String code,
    String? planSlug,
  }) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      return const PromotionCodeInvalid('not_found_or_expired');
    }
    try {
      final res = await _client.functions.invoke(
        'validate-promotion-code',
        body: {
          'code': cleanCode,
          if (planSlug != null) 'plan_slug': planSlug,
        },
      );
      final data = res.data;
      if (data is! Map) {
        throw const PromotionCodeValidatorException('empty_response');
      }
      final payload = data.cast<String, dynamic>();
      if (payload['error'] != null) {
        throw PromotionCodeValidatorException(payload['error'] as String);
      }
      if (payload['valid'] == true) {
        return PromotionCodeValid(
          AppliedPromotionCode.fromValidatePayload(payload),
        );
      }
      return PromotionCodeInvalid(
        payload['reason'] as String? ?? 'not_found_or_expired',
      );
    } on FunctionException catch (e) {
      // Rate limit y errores HTTP: tratamos como inválido pero
      // preservamos el código para diagnóstico.
      if (e.status == 429) {
        throw const PromotionCodeValidatorException('rate_limited');
      }
      throw PromotionCodeValidatorException('http_${e.status}');
    }
  }
}

class PromotionCodeValidatorException implements Exception {
  const PromotionCodeValidatorException(this.code);
  final String code;
  @override
  String toString() => 'PromotionCodeValidatorException($code)';
}
