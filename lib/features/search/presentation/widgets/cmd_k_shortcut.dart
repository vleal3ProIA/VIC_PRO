import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'search_palette.dart';

/// Wrapper que escucha `Ctrl+K` (Windows/Linux) o `Cmd+K` (macOS) y
/// abre el `SearchPalette`. Se monta una sola vez en el shell privado.
///
/// Implementación: usa `Shortcuts` + `Actions` que es la API
/// recomendada de Flutter para atajos globales. NO usa `KeyboardListener`
/// directo (eso requeriría que el child siempre tuviera el foco, lo
/// cual no se cumple cuando un dialog/menú está abierto).
class CmdKShortcut extends StatelessWidget {
  const CmdKShortcut({required this.child, super.key});

  final Widget child;

  static final _shortcut = LogicalKeySet(
    // Material/Flutter resuelve `LogicalKeyboardKey.control` para
    // Windows/Linux y `LogicalKeyboardKey.meta` para macOS. Como
    // queremos que funcione en ambos, registramos los DOS shortcuts.
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.keyK,
  );
  static final _shortcutMac = LogicalKeySet(
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.keyK,
  );

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        _shortcut: const _OpenPaletteIntent(),
        _shortcutMac: const _OpenPaletteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenPaletteIntent: CallbackAction<_OpenPaletteIntent>(
            onInvoke: (_) {
              // En web Flutter, Cmd+K NO debe abrir el diálogo del
              // navegador (search). Pero `Shortcuts` ya consume el
              // evento, así que el browser no lo recibe.
              showSearchPalette(context);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          // skipTraversal: el Focus wrapper no debe entrar en el orden
          // de Tab — solo está para que los Shortcuts tengan un nodo
          // raíz a quien atender.
          skipTraversal: true,
          child: child,
        ),
      ),
    );
  }
}

class _OpenPaletteIntent extends Intent {
  const _OpenPaletteIntent();
}

/// Etiqueta visible para mostrar al usuario "Ctrl+K" o "⌘K" según OS.
/// Usar en tooltips del icono de búsqueda.
String cmdKLabel() {
  if (defaultTargetPlatform == TargetPlatform.macOS) return '⌘K';
  return 'Ctrl+K';
}
