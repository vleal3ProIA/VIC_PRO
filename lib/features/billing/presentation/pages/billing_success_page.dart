import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';

import '../../application/billing_providers.dart';

/// `/billing/success?session_id=...`. Aterriza el usuario tras volver de
/// Stripe Checkout con éxito.
///
/// Lo que hacemos aquí:
/// 1. Invalidamos providers de billing para que la próxima carga vea la
///    suscripción nueva. (El webhook ya escribió en BD; nuestro cliente
///    solo necesita refrescar.)
/// 2. Mostramos un mensaje de éxito.
/// 3. Botón "Continue" → /home.
///
/// NO necesitamos validar el session_id contra Stripe aquí — la suscripción
/// es válida porque el webhook (que sí verifica firma) ya la creó. La
/// query param es solo informativa.
class BillingSuccessPage extends ConsumerStatefulWidget {
  const BillingSuccessPage({required this.sessionId, super.key});
  final String? sessionId;

  @override
  ConsumerState<BillingSuccessPage> createState() =>
      _BillingSuccessPageState();
}

class _BillingSuccessPageState extends ConsumerState<BillingSuccessPage> {
  @override
  void initState() {
    super.initState();
    // Refrescar suscripción y entitlements ahora — el webhook puede llegar
    // antes que esta página, pero también puede tardar 1-2 segundos.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
        ..invalidate(currentSubscriptionProvider)
        ..invalidate(currentPlanProvider)
        ..invalidate(currentEntitlementsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plan = ref.watch(currentPlanProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l.billingSuccessTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: context.colors.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  l.billingSuccessHeadline,
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  plan == null
                      ? l.billingSuccessBody
                      : l.billingSuccessBodyWithPlan(plan.name),
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => context.goNamed(RouteNames.home),
                  child: Text(l.billingSuccessContinue),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
