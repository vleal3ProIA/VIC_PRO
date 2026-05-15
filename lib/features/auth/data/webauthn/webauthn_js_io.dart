/// Stub para entornos no-web (incluidos los tests de unidad / widget que
/// corren en la VM de Dart). La app es web-only: si esto se invoca, es un
/// bug. Mantiene la misma firma que `webauthn_js_web.dart`.
Future<Map<String, dynamic>> startRegistration(
  Map<String, dynamic> options,
) async {
  throw UnsupportedError('WebAuthn solo está disponible en Flutter web.');
}

Future<Map<String, dynamic>> startAuthentication(
  Map<String, dynamic> options,
) async {
  throw UnsupportedError('WebAuthn solo está disponible en Flutter web.');
}
