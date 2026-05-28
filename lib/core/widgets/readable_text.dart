import 'package:flutter/material.dart';

/// Renderiza TEXTO PLANO (el "Original" verbatim de un documento) con tipografía
/// de lectura cómoda, en vez de mostrarlo como un bloque crudo. Reglas:
///
///   - **Párrafos**: una línea EN BLANCO separa párrafos; dentro de cada uno
///     los saltos simples se conservan (respetando la estructura del original,
///     útil en textos jurídicos con artículos línea a línea).
///   - **Cabeceras**: si una "línea suelta" parece un encabezado (corta y en
///     mayúsculas, o empieza con `Artículo`, `Título`, `Capítulo`, `Sección`,
///     `Libro`, `Tema`, etc.) se resalta en negrita y con más aire.
///   - **Sangría** de primera línea (1.2 em) en párrafos de prosa, no en
///     cabeceras.
///   - **Selección**: el conjunto va en un [SelectionArea] para poder copiar
///     varios párrafos seguidos como si fuera un único texto.
class ReadableText extends StatelessWidget {
  const ReadableText(
    this.text, {
    super.key,
    this.indentFirstLine = true,
    this.baseStyle,
  });

  final String text;
  final bool indentFirstLine;
  final TextStyle? baseStyle;

  static final RegExp _legalHeading = RegExp(
    r'^(art\.?|art[íi]culo|t[íi]tulo|cap[íi]tulo|secci[óo]n|libro|tema|chapter|article|section)\s+',
    caseSensitive: false,
  );
  static final RegExp _allCapsHeading = RegExp(
    r'^[A-ZÁÉÍÓÚÑÜ0-9 .,:;()\-/·]+$',
  );

  bool _looksLikeHeading(String paragraph) {
    final t = paragraph.trim();
    if (t.isEmpty || t.length > 90) return false;
    // Si tiene saltos internos no es heading (es un párrafo multilínea).
    if (t.contains('\n')) return false;
    if (_legalHeading.hasMatch(t)) return true;
    // ALL CAPS razonablemente corto (4-90 chars) -> heading.
    if (_allCapsHeading.hasMatch(t) && t.length >= 4) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = baseStyle ??
        (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
          height: 1.6,
          letterSpacing: 0.1,
        );
    final headingStyle = (theme.textTheme.titleSmall ?? base).copyWith(
      fontWeight: FontWeight.w800,
      height: 1.4,
    );

    // Normaliza saltos y trocea por LÍNEA EN BLANCO -> párrafo. Saltos simples
    // dentro de cada párrafo se mantienen (Text los renderiza como salto suave).
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final paragraphs = normalized
        .split(RegExp(r'\n[ \t]*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);

    final indentEm = base.fontSize != null ? base.fontSize! * 1.2 : 18.0;

    final blocks = <Widget>[];
    for (var i = 0; i < paragraphs.length; i++) {
      final p = paragraphs[i];
      final isHeading = _looksLikeHeading(p);

      if (isHeading) {
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 18, bottom: 6),
          child: Text(p, style: headingStyle),
        ),);
        continue;
      }

      // Párrafo de prosa. Sangría de primera línea opcional (no si es el primer
      // párrafo o viene justo después de una cabecera).
      final prev = i > 0 ? paragraphs[i - 1] : null;
      final afterHeading = prev != null && _looksLikeHeading(prev);
      final useIndent = indentFirstLine && i > 0 && !afterHeading;

      Widget paragraph;
      if (useIndent) {
        paragraph = Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox(width: indentEm),
              ),
              TextSpan(text: p, style: base),
            ],
          ),
          textAlign: TextAlign.justify,
        );
      } else {
        paragraph = Text(p, style: base, textAlign: TextAlign.justify);
      }

      // Separación visible "tipo salto de línea en blanco" entre párrafos.
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: paragraph,
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
}
