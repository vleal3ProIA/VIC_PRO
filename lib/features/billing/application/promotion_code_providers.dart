import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/promotion_code_validator.dart';
import '../domain/promotion_code.dart';

final promotionCodeValidatorProvider = Provider<PromotionCodeValidator>((ref) {
  return PromotionCodeValidator(ref.watch(supabaseClientProvider));
});

/// Código promocional aplicado actualmente en /billing/plans. `null` =
/// ninguno. Se hidrata con la respuesta de `validate-promotion-code` y se
/// pasa al `stripe-checkout` al iniciar el flujo. Es un StateProvider
/// porque el cliente puede aplicar/quitar el código múltiples veces sin
/// recargar.
final appliedPromotionCodeProvider =
    StateProvider<AppliedPromotionCode?>((_) => null);
