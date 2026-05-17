import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

import 'cmd_k_shortcut.dart';
import 'search_palette.dart';

/// Icono de lupa para el AppBar del shell. Tap → abre el palette.
/// El tooltip muestra el atajo de teclado según OS (Ctrl+K / ⌘K).
class SearchButton extends StatelessWidget {
  const SearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return IconButton(
      tooltip: '${l.searchTooltip} (${cmdKLabel()})',
      icon: const Icon(Icons.search),
      onPressed: () => showSearchPalette(context),
    );
  }
}
