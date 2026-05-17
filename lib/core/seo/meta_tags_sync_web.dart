import 'package:web/web.dart' as web;

/// Cache de últimos valores aplicados — evita escribir el DOM cada
/// rebuild si nada cambió.
String? _lastTitle;
String? _lastDescription;
String? _lastOgImage;
String? _lastCanonical;

/// Actualiza meta tags del documento. Idempotente: comparamos con el
/// último valor antes de escribir.
///
/// Los selectores siguen los nombres del index.html base. Si el meta
/// tag no existe (proyecto custom), lo crea on-the-fly en <head>.
void applyMetaTags({
  required String title,
  required String description,
  required String siteName,
  String? ogImageUrl,
  String? canonical,
}) {
  // ─── document.title (es lo que se ve en la pestaña) ───
  if (title.isNotEmpty && title != _lastTitle) {
    web.document.title = title;
    _lastTitle = title;
  }

  // ─── <meta name="description"> ───
  if (description != _lastDescription) {
    _setMetaContent('description', description, attrName: 'name');
    _setMetaContent('twitter:description', description, attrName: 'name');
    _setMetaContent('og:description', description, attrName: 'property');
    _lastDescription = description;
  }

  // ─── og:title / twitter:title ───
  if (title != (_lastTitle ?? '') || title.isNotEmpty) {
    _setMetaContent('og:title', title, attrName: 'property');
    _setMetaContent('twitter:title', title, attrName: 'name');
    _setMetaContent('og:site_name', siteName, attrName: 'property');
  }

  // ─── og:image / twitter:image ───
  if (ogImageUrl != null && ogImageUrl.isNotEmpty && ogImageUrl != _lastOgImage) {
    _setMetaContent('og:image', ogImageUrl, attrName: 'property');
    _setMetaContent('twitter:image', ogImageUrl, attrName: 'name');
    _lastOgImage = ogImageUrl;
  }

  // ─── canonical link ───
  if (canonical != null && canonical.isNotEmpty && canonical != _lastCanonical) {
    final existing = web.document.querySelector('link[rel="canonical"]');
    if (existing != null) {
      (existing as web.HTMLLinkElement).href = canonical;
    } else {
      final link = web.document.createElement('link') as web.HTMLLinkElement
        ..rel = 'canonical'
        ..href = canonical;
      web.document.head?.appendChild(link);
    }
    _lastCanonical = canonical;
  }

  // ─── og:url (mismo valor que canonical normalmente) ───
  if (canonical != null && canonical.isNotEmpty) {
    _setMetaContent('og:url', canonical, attrName: 'property');
  }
}

/// Setea `content` en `<meta [attrName]="key">`. Si no existe, lo crea.
void _setMetaContent(
  String key,
  String content, {
  required String attrName,
}) {
  final selector = 'meta[$attrName="$key"]';
  final existing = web.document.querySelector(selector);
  if (existing != null) {
    (existing as web.HTMLMetaElement).content = content;
    return;
  }
  // No existe → crear.
  final meta = web.document.createElement('meta') as web.HTMLMetaElement
    ..setAttribute(attrName, key)
    ..content = content;
  web.document.head?.appendChild(meta);
}
