import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:myapp/core/config/env_config.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/features/auth/data/turnstile/turnstile_js.dart';

/// Captcha de Cloudflare Turnstile embebido como widget Flutter.
///
/// Renderiza un `HtmlElementView` que contiene un `<div>` donde el SDK
/// JS de Turnstile pinta el iframe del reto. Cuando el usuario lo
/// completa (puede ser invisible si Cloudflare considera la sesión
/// "buena"), el callback [onToken] recibe el token que hay que enviar a
/// Supabase Auth en el `signUp(captchaToken: ...)`.
///
/// - Fuera de Flutter Web (tests en VM, builds móviles) este widget
///   devuelve `SizedBox.shrink()` y JAMÁS toca el SDK JS (que no
///   existe). El gating del botón en el form ignora el captcha cuando
///   `!kIsWeb` para que los tests sigan pasando sin tocarlos.
/// - Si [EnvConfig.turnstileSitekey] está vacía, el widget tampoco
///   renderiza (modo "captcha desactivado", útil en pruebas locales
///   sin cuenta de Cloudflare).
/// - [onExpired] avisa cuando el token caduca (~5 minutos según la
///   config de Cloudflare). El form debe limpiar el token guardado
///   para deshabilitar el botón hasta que el usuario re-valide.
class TurnstileWidget extends StatefulWidget {
  const TurnstileWidget({
    required this.onToken,
    super.key,
    this.onExpired,
    this.onError,
    this.theme = 'auto',
    this.size = 'normal',
    this.languageCode,
  });

  /// Token entregado por Cloudflare al pasar el reto. Se envía al backend
  /// (Supabase Auth) que valida server-side con la Secret Key.
  final void Function(String token) onToken;

  /// Llamado cuando el token caduca (Cloudflare lo invalida después de
  /// ~5 min). El captcha se resetea solo, pero el cliente debe olvidar
  /// el token viejo o el backend lo rechazará.
  final VoidCallback? onExpired;

  /// Errores reportados por el SDK (red, sitekey inválido para el
  /// dominio, dominio bloqueado, etc.).
  final void Function(String? code)? onError;

  /// `light` | `dark` | `auto` (default: sigue prefers-color-scheme).
  final String theme;

  /// `normal` (300×65) | `compact` (150×140).
  final String size;

  /// Código BCP-47 forzando el idioma del widget (p. ej. `es`). Si es
  /// null, Cloudflare detecta el del navegador. Útil cuando la app
  /// fuerza un locale distinto al del sistema.
  final String? languageCode;

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  // viewType + divId únicos por instancia para soportar múltiples
  // widgets vivos en paralelo (poco probable, pero no queremos chocar
  // con el registry de Flutter ni con ids duplicados en el DOM).
  late final String _viewType =
      'cf-turnstile-${DateTime.now().microsecondsSinceEpoch}';
  late final String _divId = 'cf-turnstile-div-$_viewType';

  TurnstileHandle? _handle;
  bool _mounting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    // CRITICO: registrar el view factory SINCRONICAMENTE aqui, antes
    // del primer build. Sin esto, HtmlElementView(viewType: _viewType)
    // no encuentra el factory y NO crea el div en el DOM, por lo que
    // turnstile.render() falla con "Unable to find a container for #...".
    // Bug confirmado en prod 2026-06-27 con Cloudflare Pages, donde
    // los assets se sirven tan rapido que el post-frame callback ya
    // tarda DEMASIADO para que el polling DOM lo cace.
    if (kIsWeb && EnvConfig.turnstileSitekey.isNotEmpty) {
      registerTurnstileView(_viewType, _divId);
    }
    // El mount real (que toca JS) se hace cuando el HtmlElementView ya
    // está en el DOM. Esperamos al primer frame post-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _mount());
  }

  Future<void> _mount() async {
    if (!kIsWeb) return;
    final sitekey = EnvConfig.turnstileSitekey;
    if (sitekey.isEmpty) return;
    if (_mounting || _handle != null) return;
    _mounting = true;
    try {
      final handle = await renderTurnstile(
        sitekey: sitekey,
        containerId: _divId,
        viewType: _viewType,
        onToken: widget.onToken,
        onExpired: widget.onExpired,
        onError: widget.onError,
        theme: widget.theme,
        size: widget.size,
        language: widget.languageCode,
      );
      if (!mounted) {
        handle.remove();
        return;
      }
      _handle = handle;
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e.toString());
      }
    } finally {
      _mounting = false;
    }
  }

  @override
  void dispose() {
    _handle?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fuera de web (tests) o sin sitekey configurada: no mostramos
    // nada. El form se encarga de no exigir token en ese caso.
    if (!kIsWeb || EnvConfig.turnstileSitekey.isEmpty) {
      return const SizedBox.shrink();
    }

    // Altura razonable según `size`. Damos algo de aire vertical para
    // que no salte el layout cuando Turnstile decide mostrar el reto.
    final double height = widget.size == 'compact' ? 150 : 72;

    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          _loadError!,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.error,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    // `HtmlElementView` requiere que el viewType esté registrado. Eso
    // sucede dentro de `renderTurnstile()` (que invoca al
    // `_registerViewIfNeeded` interno). El primer frame todavía no lo
    // tiene registrado, pero como pintamos UN frame antes que el mount
    // pida el render, Flutter espera el factory sin error.
    return SizedBox(
      width: double.infinity,
      height: height,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
