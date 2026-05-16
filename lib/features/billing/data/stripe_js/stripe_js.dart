// Facade del JS interop con Stripe.js. La implementación real está solo en
// `stripe_js_web.dart` (dart:js_interop es web-only). En VM/CI se carga
// `stripe_js_io.dart` que lanza `UnsupportedError` — el código de UI nunca
// debería llegar ahí en práctica (la pantalla solo se usa en web).
//
// Patrón conditional export: idéntico al que usamos en webauthn_js.dart.

// ignore: uri_does_not_exist, conditional_uri_does_not_exist
export 'stripe_js_io.dart'
    if (dart.library.js_interop) 'stripe_js_web.dart';
