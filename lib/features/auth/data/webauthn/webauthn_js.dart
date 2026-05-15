// Fachada con conditional import: usa el binding real con `dart:js_interop`
// en web, y un stub que lanza `UnsupportedError` en otras plataformas
// (necesario para que la app compile en la VM de Dart, p. ej. al correr
// los tests).
export 'webauthn_js_io.dart'
    if (dart.library.js_interop) 'webauthn_js_web.dart';
