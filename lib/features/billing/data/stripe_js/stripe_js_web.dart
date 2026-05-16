// Implementación real del wrapper JS interop para Stripe Embedded Checkout.
//
// Carga Stripe.js (vía web/index.html), llama a `Stripe(publishableKey)`,
// luego `stripe.initEmbeddedCheckout({clientSecret})`, y monta el widget
// en un div creado por HtmlElementView de Flutter.
//
// API de Stripe usada:
//   https://docs.stripe.com/payments/checkout/how-checkout-works?ui=embedded
//
// La parte de `globalContext.hasProperty(...)` evita explotar si el script
// de Stripe.js aún no se ha terminado de cargar (lo cargamos async).

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

// ─── External JS bindings ─────────────────────────────────────────────────

/// `window.Stripe(publishableKey)` — devuelve el "stripe object".
@JS('Stripe')
external _StripeJsModule _stripeFactory(String publishableKey);

/// `null` cuando Stripe.js aún no ha terminado de cargarse (es <script async>).
@JS('Stripe')
external JSAny? _stripeGlobal;

extension type _StripeJsModule._(JSObject _) implements JSObject {
  /// `stripe.initEmbeddedCheckout({clientSecret})` → promise<checkout>.
  external JSPromise<_StripeCheckoutHandle> initEmbeddedCheckout(
    _InitEmbeddedOptions options,
  );
}

@JS()
@anonymous
extension type _InitEmbeddedOptions._(JSObject _) implements JSObject {
  external factory _InitEmbeddedOptions({required String clientSecret});
}

extension type _StripeCheckoutHandle._(JSObject _) implements JSObject {
  external void mount(String selector);
  external void destroy();
}

// ─── Public API ─────────────────────────────────────────────────────────────

/// Handle del widget Embedded Checkout montado. La página llama `destroy()`
/// al desmontarse para liberar el iframe y los event listeners.
class StripeEmbeddedController {
  StripeEmbeddedController._(this._handle);

  final _StripeCheckoutHandle _handle;

  void destroy() {
    try {
      _handle.destroy();
    } catch (_) {
      // Si Stripe ya lo destruyó internamente, ignoramos.
    }
  }
}

/// Registry per-proceso de viewTypes ya registrados. Registrar dos veces
/// el mismo viewType lanza, así que llevamos cuenta.
final Set<String> _registeredViews = <String>{};

void _registerViewIfNeeded(String viewType, String divId) {
  if (_registeredViews.contains(viewType)) return;
  _registeredViews.add(viewType);
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final div = web.HTMLDivElement()
        ..id = divId
        ..style.width = '100%'
        ..style.minHeight = '600px';
      return div;
    },
  );
}

bool _stripeLoaded() => _stripeGlobal != null;

/// Monta el widget Embedded Checkout dentro del div con id [containerId].
/// El HtmlElementView con viewType [viewType] debe estar renderizado ANTES
/// de llamar a este método; la página de checkout lo arregla esperando
/// un frame antes de invocar.
///
/// Espera hasta 5 segundos a que `window.Stripe` esté disponible (Stripe.js
/// se carga async en web/index.html).
Future<StripeEmbeddedController> mountEmbeddedCheckout({
  required String publishableKey,
  required String clientSecret,
  required String containerId,
  required String viewType,
}) async {
  _registerViewIfNeeded(viewType, containerId);

  // Esperar a que Stripe.js termine de cargar (web/index.html lo trae
  // como async, así que puede no estar disponible inmediatamente).
  for (var i = 0; i < 50; i++) {
    if (_stripeLoaded()) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!_stripeLoaded()) {
    throw StateError(
      'Stripe.js no se cargó en 5 segundos. Verifica que el <script> '
      'esté en web/index.html y que el navegador puede acceder a '
      'js.stripe.com.',
    );
  }

  final stripe = _stripeFactory(publishableKey);
  final checkout = await stripe
      .initEmbeddedCheckout(
        _InitEmbeddedOptions(clientSecret: clientSecret),
      )
      .toDart;

  // Esperar 2 frames para asegurarnos de que el HtmlElementView ya creó
  // el div en el DOM antes de pedirle a Stripe que monte.
  await Future<void>.delayed(const Duration(milliseconds: 32));
  checkout.mount('#$containerId');

  return StripeEmbeddedController._(checkout);
}
