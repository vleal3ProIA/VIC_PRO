import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../application/search_registry.dart';
import '../../domain/search_result.dart';

/// Modal centrado tipo Slack/Linear/Notion con un input arriba y los
/// resultados debajo agrupados por sección. Se navega con `↑` `↓`,
/// se ejecuta con `Enter`, se cierra con `Esc`.
///
/// Para abrirlo:
/// ```dart
/// showSearchPalette(context);
/// ```
///
/// Internamente usa `showGeneralDialog` (no `showDialog`) para tener
/// el control sobre el barrierColor y la transición fade.
Future<void> showSearchPalette(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: context.l10n.searchTooltip,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, __, ___) => const _SearchPalette(),
    transitionBuilder: (_, anim, __, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(anim),
          child: child,
        ),
      );
    },
  );
}

class _SearchPalette extends ConsumerStatefulWidget {
  const _SearchPalette();

  @override
  ConsumerState<_SearchPalette> createState() => _SearchPaletteState();
}

class _SearchPaletteState extends ConsumerState<_SearchPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _controller.addListener(() => setState(() => _selectedIndex = 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event, List<SearchResult> results) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, results.length - 1);
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, results.length - 1);
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (results.isNotEmpty) {
        results[_selectedIndex].onSelect(context);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final registry = ref.watch(searchRegistryProvider);
    final query = _controller.text;
    final results = registry.search(ref, l, query);
    final grouped = registry.groupBySection(results);

    return Align(
      alignment: const Alignment(0, -0.5),
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 480),
          child: Card(
            elevation: 12,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: KeyboardListener(
              focusNode: FocusNode(),
              autofocus: true,
              onKeyEvent: (e) => _onKey(e, results),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      style: context.textTheme.titleMedium,
                      decoration: InputDecoration(
                        icon: const Icon(Icons.search),
                        hintText: l.searchHint,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: results.isEmpty
                        ? _Empty(message: l.searchEmpty(query))
                        : _ResultsList(
                            grouped: grouped,
                            results: results,
                            selectedIndex: _selectedIndex,
                            onTap: (idx) => results[idx].onSelect(context),
                            onHover: (idx) =>
                                setState(() => _selectedIndex = idx),
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _HintChip(label: '↑↓', text: l.searchHintNavigate),
                        const SizedBox(width: 12),
                        _HintChip(label: '↵', text: l.searchHintSelect),
                        const SizedBox(width: 12),
                        _HintChip(label: 'esc', text: l.searchHintClose),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.grouped,
    required this.results,
    required this.selectedIndex,
    required this.onTap,
    required this.onHover,
  });
  final Map<String, List<SearchResult>> grouped;
  final List<SearchResult> results;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    // Construimos la lista plana de widgets: por cada sección, un
    // header + sus filas. Mantenemos el `flatIndex` para saber qué
    // resultado pintar como seleccionado.
    final children = <Widget>[];
    var flatIndex = 0;
    for (final entry in grouped.entries) {
      children.add(_SectionHeader(label: entry.key));
      for (final r in entry.value) {
        final idx = flatIndex;
        children.add(
          _ResultTile(
            result: r,
            selected: idx == selectedIndex,
            onTap: () => onTap(idx),
            onHover: () => onHover(idx),
          ),
        );
        flatIndex++;
      }
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: children,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: context.textTheme.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });
  final SearchResult result;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Container(
        color: selected
            ? context.colors.primaryContainer.withValues(alpha: 0.6)
            : null,
        child: ListTile(
          dense: true,
          leading: Icon(result.icon),
          title: Text(result.title),
          subtitle: result.subtitle == null ? null : Text(result.subtitle!),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          message,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.label, required this.text});
  final String label;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
