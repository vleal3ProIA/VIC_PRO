import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';

import '../../application/billing_providers.dart';
import '../../data/billing_datasource.dart';
import '../../data/stripe_js/stripe_js.dart';

/// Pantalla `/billing/checkout?plan_slug=pro&billing_period=monthly`.
///
/// Embebe el widget **Stripe Embedded Checkout** dentro de la propia app
/// — el usuario NO sale a `checkout.stripe.com`. Cuando completa el pago,
/// Stripe redirige al `return_url` que es `/billing/success`.
///
/// Flujo:
///   1. Llama a la Edge Function `stripe-checkout` con `ui_mode: embedded`.
///   2. Recibe `client_secret` y `publishable_key`.
///   3. Carga Stripe.js (ya en `web/index.html`) y monta el widget en un
///      `HtmlElementView`.
///   4. Stripe se encarga del UI de tarjeta + 3DS + Apple Pay + etc.
///   5. Al terminar, Stripe navega solo a return_url (success page).
///
/// **Solo funciona en Flutter Web.** En mobile mostraría error porque el
/// JS interop devuelve un stub.
class EmbeddedCheckoutPage extends ConsumerStatefulWidget {
  const EmbeddedCheckoutPage({
    required this.planSlug,
    required this.billingPeriod,
    this.stripePromotionCodeId,
    super.key,
  });

  final String planSlug;
  final String billingPeriod;

  /// Si llega no-null, se pasa al `stripe-checkout` para aplicar el
  /// descuento como `discounts: [{promotion_code}]` en la session.
  /// Validado previamente en `/billing/plans` por la Edge Function
  /// `validate-promotion-code`.
  final String? stripePromotionCodeId;

  @override
  ConsumerState<EmbeddedCheckoutPage> createState() =>
      _EmbeddedCheckoutPageState();
}

class _EmbeddedCheckoutPageState extends ConsumerState<EmbeddedCheckoutPage> {
  static const _containerDivId = 'stripe-checkout-container';
  static const _viewType = 'stripe-checkout-view';

  StripeEmbeddedController? _controller;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!kIsWeb) {
      setState(() => _error = context.l10n.checkoutNotSupportedNonWeb);
      return;
    }
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      setState(() => _error = context.l10n.checkoutSessionExpired);
      return;
    }
    try {
      // 1) Pedir client_secret + publishable_key al backend.
      final base = Uri.base;
      final returnUrl = Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort && base.port != 80 && base.port != 443
            ? base.port
            : null,
        path: RoutePaths.billingSuccess,
        queryParameters: const {'session_id': '{CHECKOUT_SESSION_ID}'},
      ).toString();
      final ds = ref.read(billingDataSourceProvider);
      final session = await ds.createEmbeddedCheckoutSession(
        tenantId: tenantId,
        planSlug: widget.planSlug,
        billingPeriod: widget.billingPeriod,
        returnUrl: returnUrl,
        stripePromotionCodeId: widget.stripePromotionCodeId,
      );

      final pk = session.publishableKey;
      if (pk == null || pk.isEmpty) {
        if (!mounted) return;
        setState(
          () => _error = context.l10n.checkoutPublishableKeyMissing,
        );
        return;
      }

      // 2) Forzar un frame para que el HtmlElementView de abajo (que ya
      //    aparece en el árbol porque _ready=true) se renderice antes de
      //    pedir a Stripe que monte.
      setState(() => _ready = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // 3) Mount.
      final controller = await mountEmbeddedCheckout(
        publishableKey: pk,
        clientSecret: session.clientSecret,
        containerId: _containerDivId,
        viewType: _viewType,
      );
      _controller = controller;
    } on BillingException catch (e) {
      if (!mounted) return;
      setState(() => _error = _mapError(e.code));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '${context.l10n.checkoutGenericError}: $e');
    }
  }

  String _mapError(String code) {
    final l = context.l10n;
    return switch (code) {
      'stripe_not_configured' => l.plansStripeNotConfigured,
      'rate_limited' => l.plansRateLimited,
      'not_admin' || 'not_member' => l.plansNotAdmin,
      _ => l.checkoutGenericError,
    };
  }

  @override
  void dispose() {
    _controller?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.plans),
        ),
        title: Text(l.checkoutTitle),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _error != null
                ? _ErrorBox(message: _error!)
                : !_ready
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 24),
                          Text(l.checkoutLoading),
                        ],
                      )
                    : const _StripeContainer(
                        viewType: _viewType,
                        containerId: _containerDivId,
                      ),
          ),
        ),
      ),
    );
  }
}

class _StripeContainer extends StatelessWidget {
  const _StripeContainer({required this.viewType, required this.containerId});

  final String viewType;
  final String containerId;

  @override
  Widget build(BuildContext context) {
    // `HtmlElementView` requiere que el viewType esté registrado. Esto se
    // hace dentro de `mountEmbeddedCheckout` (que invoca a
    // `_registerViewIfNeeded`). Si la página se construye antes del
    // primer mount, no pasa nada: el HtmlElementView espera el factory.
    return SizedBox(
      width: double.infinity,
      height: 700,
      child: HtmlElementView(viewType: viewType),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: context.colors.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: context.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () =>
                  GoRouter.of(context).goNamed(RouteNames.plans),
              child: Text(context.l10n.actionGoBack),
            ),
          ],
        ),
      );
}
