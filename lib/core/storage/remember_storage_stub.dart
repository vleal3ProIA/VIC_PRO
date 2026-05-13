/// Stub para plataformas no-web. En móvil/desktop el storage de auth
/// siempre usa la implementación por defecto del SDK (SharedPreferences),
/// que es persistente — no hace falta "remember me" porque la app es
/// instalable y el usuario decide cuándo desinstalarla.
class WebStorageHelper {
  WebStorageHelper._();

  static String? getItem(String key, {required bool persistent}) => null;
  static void setItem(String key, String value, {required bool persistent}) {}
  static void removeItem(String key) {}
}
