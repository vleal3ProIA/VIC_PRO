import 'package:web/web.dart' as web;

/// Última URL aplicada al `<link rel="icon">`. Evita escribir el DOM
/// en cada rebuild si la URL no cambió.
String? _lastFaviconUrl;

/// Último título aplicado al `<title>`. Mismo motivo.
String? _lastTitle;

/// Aplica el branding al DOM del navegador:
///   - `document.title` = nombre comercial (afecta a la pestaña + bookmarks)
///   - `<link rel="icon">.href` = favicon URL (si está configurado)
///
/// Idempotente: ignora llamadas con los mismos valores.
void applyToDocument({required String title, String? faviconUrl}) {
  // 1) Title
  if (title.isNotEmpty && title != _lastTitle) {
    web.document.title = title;
    _lastTitle = title;
  }

  // 2) Favicon: solo si hay URL configurada. Si está vacía, dejamos
  //    el favicon estático del index.html (default del proyecto).
  if (faviconUrl != null && faviconUrl.isNotEmpty && faviconUrl != _lastFaviconUrl) {
    final existing = web.document.querySelector('link[rel="icon"]');
    if (existing != null) {
      // El link ya existe (definido en index.html) → solo cambiamos su href.
      (existing as web.HTMLLinkElement).href = faviconUrl;
    } else {
      // No existe → lo creamos.
      final link = web.document.createElement('link') as web.HTMLLinkElement
        ..rel = 'icon'
        ..href = faviconUrl;
      web.document.head?.appendChild(link);
    }
    _lastFaviconUrl = faviconUrl;
  }
}
