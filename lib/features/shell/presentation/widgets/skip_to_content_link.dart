import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

/// "Skip to main content" link estándar de a11y web. Aparece SOLO cuando
/// recibe foco por teclado (primer Tab al cargar la página) y permite
/// saltarse la cabecera + el rail de navegación para ir directo al
/// contenido principal.
///
/// Patrón estándar WCAG 2.4.1 (Bypass Blocks). Implementado siguiendo
/// la guía de Flutter Web a11y: invisible visualmente pero presente en
/// el árbol de Semantics y en el orden de Tab.
///
/// Uso:
/// ```dart
/// final mainFocus = FocusNode(debugLabel: 'main-content');
/// Stack(children: [
///   YourScaffold(body: Focus(focusNode: mainFocus, child: ...)),
///   SkipToContentLink(targetFocusNode: mainFocus),
/// ])
/// ```
class SkipToContentLink extends StatefulWidget {
  const SkipToContentLink({required this.targetFocusNode, super.key});

  /// El FocusNode al que se moverá el foco cuando el usuario active el
  /// skip link. Tiene que estar adjunto a un widget Focus en el cuerpo
  /// principal de la página.
  final FocusNode targetFocusNode;

  @override
  State<SkipToContentLink> createState() => _SkipToContentLinkState();
}

class _SkipToContentLinkState extends State<SkipToContentLink> {
  late final FocusNode _selfFocus =
      FocusNode(debugLabel: 'skip-to-content-link');

  @override
  void initState() {
    super.initState();
    _selfFocus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _selfFocus.removeListener(_onFocusChange);
    _selfFocus.dispose();
    super.dispose();
  }

  void _onFocusChange() => setState(() {});

  void _activate() {
    widget.targetFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _selfFocus.hasFocus;
    // `Offstage` saca el widget del layout cuando no tiene foco, pero
    // sigue presente en el árbol de Semantics y como destino del primer
    // Tab. Cuando recibe foco, se muestra en la esquina superior izquierda
    // sobre el AppBar — patrón visual idéntico al de github.com, gov.uk,
    // microsoft.com, etc.
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: Offstage(
        offstage: !visible,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.primary,
            child: InkWell(
              focusNode: _selfFocus,
              onTap: _activate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  context.l10n.a11ySkipToContent,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
