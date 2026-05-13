import 'package:web/web.dart' as web;

/// Implementación web del helper de storage que conmuta entre
/// `localStorage` (persistente entre sesiones del navegador) y
/// `sessionStorage` (se borra al cerrar la pestaña).
class WebStorageHelper {
  WebStorageHelper._();

  static web.Storage _backend({required bool persistent}) =>
      persistent ? web.window.localStorage : web.window.sessionStorage;

  static String? getItem(String key, {required bool persistent}) {
    return _backend(persistent: persistent).getItem(key);
  }

  static void setItem(String key, String value, {required bool persistent}) {
    _backend(persistent: persistent).setItem(key, value);
    // Aseguramos que solo hay UNA copia: si guardamos en local, borramos
    // de session, y viceversa.
    _backend(persistent: !persistent).removeItem(key);
  }

  static void removeItem(String key) {
    web.window.localStorage.removeItem(key);
    web.window.sessionStorage.removeItem(key);
  }
}
