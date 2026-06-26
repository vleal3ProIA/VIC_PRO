// Implementación real del wrapper JS interop para Cloudflare Turnstile.
//
// Carga el SDK desde `web/index.html`:
//   <script src="https://challenges.cloudflare.com/turnstile/v0/api.js"
//           async defer></script>
//
// Expone `window.turnstile` con:
//   - turnstile.render(container, options) → widgetId
//   - turnstile.reset(widgetId)
//   - turnstile.remove(widgetId)
//
// Docs: https://developers.cloudflare.com/turnstile/get-started/client-side-rendering/
//
// El widget se monta en un div creado por `HtmlElementView` de Flutter.
// Cuando el usuario completa el reto, Turnstile llama al callback que
// le pasamos con un token (string). Ese token va a Supabase Auth en el
// signUp; Supabase lo valida server-side contra Cloudflare con la
// Secret Key configurada en Dashboard → Auth → Bot protection.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

// ─── External JS bindings ─────────────────────────────────────────────────

/// `window.turnstile` — `null` mientras el script async aún no terminó
/// de cargarse. Comprobamos con un poll antes de invocar `render()`.
@JS('turnstile')
external JSAny? _turnstileGlobal;

extension type _TurnstileApi._(JSObject _) implements JSObject {
  /// Devuelve el `widgetId` (string opaco).
  external JSAny? render(JSAny container, JSObject options);
  external void reset(JSAny widgetId);
  external void remove(JSAny widgetId);
}

_TurnstileApi get _turnstile => _turnstileGlobal! as _TurnstileApi;

bool _turnstileLoaded() => _turnstileGlobal != null;

// ─── Public API ─────────────────────────────────────────────────────────────

/// Handle del widget montado. Permite resetear (p. ej. cuando el token
/// caduca) o eliminar el iframe al desmontar el widget Flutter.
class TurnstileHandle {
  TurnstileHandle._(this._widgetId);

  final JSAny _widgetId;

  void reset() {
    try {
      _turnstile.reset(_widgetId);
    } catch (_) {
      // Si el script no estaba o ya se eliminó, ignoramos: el reset es
      // best-effort para refrescar el token caducado.
    }
  }

  void remove() {
    try {
      _turnstile.remove(_widgetId);
    } catch (_) {
      // Idem: el remove puede llegar tarde si Cloudflare ya purgó el
      // widget al cambiar de pestaña, o si Flutter destruyó el host div.
    }
  }
}

/// Registry per-proceso de viewTypes ya registrados. Registrar dos veces
/// el mismo viewType lanza, así que llevamos cuenta (igual patrón que
/// Stripe Embedded Checkout).
final Set<String> _registeredViews = <String>{};

void _registerViewIfNeeded(String viewType, String divId) {
  if (_registeredViews.contains(viewType)) return;
  _registeredViews.add(viewType);
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      // El widget de Turnstile mide ~300×65 px en `normal` y ~150×140 px
      // en `compact`. Dejamos el div sin tamaño explícito para que herede
      // del contenedor Flutter (`SizedBox` con altura razonable).
      final div = web.HTMLDivElement()
        ..id = divId
        ..style.width = '100%'
        ..style.display = 'flex'
        ..style.justifyContent = 'center';
      return div;
    },
  );
}

/// Monta el widget de Turnstile dentro del div con id [containerId].
/// El [HtmlElementView] con viewType [viewType] debe estar renderizado
/// ANTES de llamar a este método (el caller espera un frame antes).
///
/// Espera hasta 5 segundos a que `window.turnstile` esté disponible (el
/// script se carga async en web/index.html).
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
}) async {
  _registerViewIfNeeded(viewType, containerId);

  // Esperar a que el SDK termine de cargar. `async defer` puede tardar
  // un poco en redes lentas o cuando bloquea un service worker.
  for (var i = 0; i < 50; i++) {
    if (_turnstileLoaded()) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!_turnstileLoaded()) {
    throw StateError(
      'Cloudflare Turnstile no se cargó en 5 segundos. Verifica que el '
      '<script> esté en web/index.html y que el navegador puede acceder '
      'a challenges.cloudflare.com.',
    );
  }

  // Esperar a que el HtmlElementView haya pintado el div en el DOM.
  // CRITICO: el delay fijo de 32ms no es suficiente cuando Cloudflare/CDN
  // sirve el bundle muy rapido y los frames se renderizan a destiempo
  // (bug observado en prod tras N4: TurnstileError 'Unable to find a
  // container for #cf-turnstile-div-...'). Polling explicito del DOM:
  for (var i = 0; i < 50; i++) {
    if (web.document.getElementById(containerId) != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (web.document.getElementById(containerId) == null) {
    throw StateError(
      'Container #$containerId no aparece en el DOM tras 2.5s. '
      'HtmlElementView no se rendero - revisar lifecycle del widget.',
    );
  }

  // Construimos el objeto de opciones como JSObject "plano" porque
  // varias keys llevan guion ('error-callback', 'expired-callback') y
  // no son válidas como nombres de campo en una extension type Dart.
  final opts = JSObject();
  opts['sitekey'] = sitekey.toJS;
  opts['theme'] = theme.toJS;
  opts['size'] = size.toJS;
  if (language != null) opts['language'] = language.toJS;
  if (action != null) opts['action'] = action.toJS;

  opts['callback'] = ((JSString token) {
    onToken(token.toDart);
  }).toJS;

  if (onExpired != null) {
    opts['expired-callback'] = (() {
      onExpired();
    }).toJS;
  }

  if (onError != null) {
    opts['error-callback'] = ((JSAny? code) {
      onError(code is JSString ? code.toDart : null);
    }).toJS;
  }

  final widgetId = _turnstile.render('#$containerId'.toJS, opts);
  if (widgetId == null) {
    throw StateError(
      'turnstile.render() devolvió null. Posible causa: el contenedor '
      '#$containerId no estaba aún en el DOM, o el sitekey es inválido '
      'para este dominio.',
    );
  }
  return TurnstileHandle._(widgetId);
}
