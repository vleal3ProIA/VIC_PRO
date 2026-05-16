// Stub para entornos no-web. Llamar a esto significa que algo intentó
// montar Embedded Checkout fuera de Flutter Web. La página de checkout
// solo se renderiza en web; este código nunca se ejecuta en práctica.
//
// El `class` y la signatura coinciden con la del web para que el código
// importador compile en VM (tests, CI).

class StripeEmbeddedController {
  void destroy() {
    throw UnsupportedError('StripeEmbeddedController solo está disponible en web');
  }
}

Future<StripeEmbeddedController> mountEmbeddedCheckout({
  required String publishableKey,
  required String clientSecret,
  required String containerId,
  required String viewType,
}) {
  throw UnsupportedError('Embedded Checkout solo está disponible en web');
}
