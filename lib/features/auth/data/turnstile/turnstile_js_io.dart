// Stub para entornos no-web (incluidos los tests de unidad/widget que
// corren en la VM de Dart). El captcha de Turnstile es web-only: si
// algo invoca esto, es un bug. Mantiene la misma firma que
// `turnstile_js_web.dart` para que el código importador compile en VM.

/// Handle del widget de Turnstile montado. Permite resetear o eliminar
/// el iframe cuando el usuario navega fuera.
class TurnstileHandle {
  void reset() {
    throw UnsupportedError('Turnstile solo está disponible en Flutter web.');
  }

  void remove() {
    throw UnsupportedError('Turnstile solo está disponible en Flutter web.');
  }
}

/// Monta el widget de Turnstile dentro del div con id [containerId].
/// El [HtmlElementView] con viewType [viewType] debe estar renderizado
/// ANTES de llamar (igual que con Stripe Embedded Checkout).
Future<TurnstileHandle> renderTurnstile({
  required String sitekey,
  required String containerId,
  required String viewType,
  required void Function(String token) onToken,
  void Function()? onExpired,
  void Function(String? code)? onError,
  String theme = 'auto',
  String size = 'normal',
  String? language,
  String? action,
}) {
  throw UnsupportedError('Turnstile solo está disponible en Flutter web.');
}

/// Registra el view factory de Flutter web ANTES del primer build (debe
/// llamarse en initState). Sin esto, HtmlElementView no encuentra el
/// factory y el div nunca aparece en el DOM. Stub en VM (no-op).
void registerTurnstileView(String viewType, String divId) {
  // No-op en VM/tests; el TurnstileWidget tampoco llega aqui porque ya
  // gatea con `!kIsWeb`.
}
