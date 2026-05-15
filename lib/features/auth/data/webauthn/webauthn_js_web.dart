import 'dart:async';
import 'dart:js_interop';

/// Bindings JS para `@simplewebauthn/browser` (cargado por `web/index.html`).
///
/// La librería hace de capa fina sobre `navigator.credentials` y se ocupa de
/// la codificación base64url ↔ ArrayBuffer que la API nativa requiere. Aquí
/// solo hace falta convertir las Maps Dart en objetos JS y de vuelta.
@JS('SimpleWebAuthnBrowser.startRegistration')
external JSPromise<JSObject> _jsStartRegistration(JSObject args);

@JS('SimpleWebAuthnBrowser.startAuthentication')
external JSPromise<JSObject> _jsStartAuthentication(JSObject args);

/// Dispara la ceremonia de registro (`navigator.credentials.create`) con las
/// opciones que vienen del servidor (Edge Function `webauthn` action
/// `register-options`). Devuelve la respuesta del navegador (lista para
/// reenviarla a `register-verify`).
///
/// Lanza si el usuario cancela o el navegador no soporta passkeys.
Future<Map<String, dynamic>> startRegistration(
  Map<String, dynamic> options,
) async {
  final args = <String, dynamic>{'optionsJSON': options}.jsify()! as JSObject;
  final result = await _jsStartRegistration(args).toDart;
  return (result.dartify()! as Map).cast<String, dynamic>();
}

/// Dispara la ceremonia de autenticación (`navigator.credentials.get`).
Future<Map<String, dynamic>> startAuthentication(
  Map<String, dynamic> options,
) async {
  final args = <String, dynamic>{'optionsJSON': options}.jsify()! as JSObject;
  final result = await _jsStartAuthentication(args).toDart;
  return (result.dartify()! as Map).cast<String, dynamic>();
}
