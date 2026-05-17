/// Stub no-op para plataformas no-web (mobile / desktop). En esos
/// targets no existe `dart:html`, así que la implementación real está
/// en el archivo `_web.dart` y aquí solo proporcionamos un símbolo
/// con la misma firma para que el conditional import compile.
void applyToDocument({required String title, String? faviconUrl}) {
  // no-op
}
