import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

/// Dialog que muestra los keyboard shortcuts disponibles en la app.
/// Se abre desde el menú "?" del AppBar. Lista pensada para crecer
/// según vayamos añadiendo más atajos — cada feature que registre uno
/// nuevo debería añadir una línea aquí.
class KeyboardShortcutsDialog extends StatelessWidget {
  const KeyboardShortcutsDialog({super.key});

  /// `true` si estamos en macOS (real o web en Safari/Chrome con UA Mac).
  /// Determina si mostramos ⌘ vs Ctrl. Best-effort en web.
  bool get _isMacLike {
    if (kIsWeb) {
      // En web no podemos detectar fiable sin JS interop. Default Ctrl.
      // El propio CmdKShortcut acepta ambos modificadores, así que el
      // texto que mostramos es informativo, no funcional.
      return false;
    }
    try {
      return Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final modKey = _isMacLike ? '⌘' : 'Ctrl';

    final shortcuts = <_Shortcut>[
      _Shortcut(
        keys: [modKey, 'K'],
        description: l.shortcutSearchPalette,
      ),
      _Shortcut(
        keys: ['Tab'],
        description: l.shortcutNavigate,
      ),
      _Shortcut(
        keys: ['Enter'],
        description: l.shortcutConfirm,
      ),
      _Shortcut(
        keys: ['Esc'],
        description: l.shortcutDismiss,
      ),
    ];

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.keyboard_outlined),
          const SizedBox(width: 8),
          Text(l.shortcutsDialogTitle),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.shortcutsDialogIntro,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (final s in shortcuts) _ShortcutRow(shortcut: s),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
        ),
      ],
    );
  }
}

class _Shortcut {
  const _Shortcut({required this.keys, required this.description});
  final List<String> keys;
  final String description;
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.shortcut});
  final _Shortcut shortcut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shortcut.description,
              style: context.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          // Pinta cada tecla como un "kbd" pill.
          for (var i = 0; i < shortcut.keys.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '+',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            _KbdChip(label: shortcut.keys[i]),
          ],
        ],
      ),
    );
  }
}

class _KbdChip extends StatelessWidget {
  const _KbdChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
