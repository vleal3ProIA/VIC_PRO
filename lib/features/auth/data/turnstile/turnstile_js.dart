// Facade del JS interop con Cloudflare Turnstile. La implementación real
// está solo en `turnstile_js_web.dart` (dart:js_interop es web-only). En
// VM/CI (tests) se carga `turnstile_js_io.dart` que lanza
// `UnsupportedError` — el widget jamás se monta fuera de web porque
// `TurnstileWidget` guarda con `kIsWeb`.
//
// Patrón conditional export: idéntico al que usamos en webauthn_js.dart
// y stripe_js.dart.

// ignore: uri_does_not_exist, conditional_uri_does_not_exist
export 'turnstile_js_io.dart'
    if (dart.library.js_interop) 'turnstile_js_web.dart';
