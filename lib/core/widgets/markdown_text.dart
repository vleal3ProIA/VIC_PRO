import 'package:flutter/material.dart';

/// Render Markdown LIGERO y seleccionable para el contenido generado por IA
/// (Explicado / Resumen). No añade dependencias: cubre el subconjunto que el
/// modelo emite de forma predecible —encabezados (#, ##, ###), listas con
/// viñetas (-, *, •), listas numeradas (1.), **negrita**, regla horizontal
/// (---) y párrafos—. El "Original" verbatim NO usa este widget (se muestra
/// tal cual con [SelectableText]).
///
/// El conjunto va dentro de un [SelectionArea] para poder seleccionar y
/// copiar el texto de corrido aunque internamente sean varios widgets.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.baseStyle});

  final String data;
  final TextStyle? baseStyle;

  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
  static final RegExp _ordered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
  static final RegExp _rule = RegExp(r'^\s*([-*_])\1{2,}\s*$');
  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = baseStyle ??
        theme.textTheme.bodyMedium?.copyWith(height: 1.5) ??
        const TextStyle(height: 1.5);

    final lines = data.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final blocks = <Widget>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: 8));
        continue;
      }

      final rule = _rule.firstMatch(line);
      if (rule != null) {
        blocks.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1),
        ),);
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final text = heading.group(2)!.trim();
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 10, bottom: 4),
          child: Text.rich(
            TextSpan(children: _inline(text, _headingStyle(theme, base, level))),
          ),
        ),);
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        blocks.add(_listItem(context, base, marker: '•', text: bullet.group(1)!));
        continue;
      }

      final ordered = _ordered.firstMatch(line);
      if (ordered != null) {
        blocks.add(_listItem(
          context,
          base,
          marker: '${ordered.group(1)}.',
          text: ordered.group(2)!,
        ),);
        continue;
      }

      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text.rich(TextSpan(children: _inline(line.trim(), base))),
      ),);
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: blocks,
      ),
    );
  }

  Widget _listItem(
    BuildContext context,
    TextStyle base, {
    required String marker,
    required String text,
  }) {
    final markerStyle = base.copyWith(
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.primary,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(marker, style: markerStyle),
          ),
          Expanded(
            child: Text.rich(TextSpan(children: _inline(text.trim(), base))),
          ),
        ],
      ),
    );
  }

  TextStyle _headingStyle(ThemeData theme, TextStyle base, int level) {
    final t = theme.textTheme;
    switch (level) {
      case 1:
        return (t.titleMedium ?? base).copyWith(fontWeight: FontWeight.w800);
      case 2:
        return (t.titleSmall ?? base).copyWith(fontWeight: FontWeight.w700);
      default:
        return base.copyWith(fontWeight: FontWeight.w700);
    }
  }

  /// Convierte el texto en spans, resolviendo **negrita** / __negrita__.
  List<InlineSpan> _inline(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _bold.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: style));
      }
      final bold = m.group(1) ?? m.group(2) ?? '';
      spans.add(TextSpan(
        text: bold,
        style: style.copyWith(fontWeight: FontWeight.w700),
      ),);
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: text, style: style));
    return spans;
  }
}
