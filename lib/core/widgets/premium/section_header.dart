// ignore_for_file: always_put_required_named_parameters_first
// Ver razonamiento en premium_card.dart.

import 'package:flutter/material.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Header de seccion estilo Stripe / Linear: titulo grande con letter
/// spacing negativo + subtitulo descriptivo opcional + slot a la derecha
/// para una accion (ej. boton "View all").
///
/// Jerarquia visual: el titulo usa `headlineSmall` por defecto (24-28px
/// segun escala), el subtitulo `bodyMedium` con `onSurfaceVariant`.
///
/// **Uso tipico**:
/// ```dart
/// SectionHeader(
///   title: 'Recent activity',
///   subtitle: 'Your latest actions in the workspace',
///   trailing: TextButton(
///     onPressed: () => context.goNamed(RouteNames.activity),
///     child: Text('View all'),
///   ),
/// )
/// ```
///
/// **Variantes de tamano**: con `compact: true` el titulo cae a
/// `titleLarge` (~20px). Util para sub-secciones dentro de una pagina
/// que ya tiene su header principal.
///
/// **Responsive**: si el trailing widget no cabe en mobile, se envuelve
/// a una segunda linea automaticamente (uso de Wrap).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.compact = false,
    this.padding = EdgeInsets.zero,
  });

  /// Texto del titulo. Bold, letter-spacing -0.5.
  final String title;

  /// Subtitulo opcional. Color secundario, 1-2 lineas tipicamente.
  final String? subtitle;

  /// Slot a la derecha para una accion. Tipicamente un TextButton o
  /// IconButton. Si null, ocupa todo el ancho el titulo.
  final Widget? trailing;

  /// Version mas pequena del header para sub-secciones.
  final bool compact;

  /// Padding exterior. Default cero -- el caller controla spacing.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final titleStyle = compact
        ? theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1.2,
          )
        : theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.15,
          );

    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.4,
    );

    // Construimos primero el bloque de texto (titulo + subtitulo).
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: titleStyle),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: subtitleStyle),
        ],
      ],
    );

    // Si no hay trailing, devolvemos solo el bloque.
    if (trailing == null) {
      return Padding(padding: padding, child: textBlock);
    }

    // Con trailing: usamos Wrap para que en mobile, si el trailing no
    // cabe, se envuelva a una segunda linea en lugar de overflow.
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Heuristica: si el ancho del contenedor es < 480 (mobile),
          // usamos Column. Si no, Row con Spacer.
          final isNarrow = constraints.maxWidth < 480;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                textBlock,
                const SizedBox(height: AppSpacing.sm),
                trailing!,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: textBlock),
              const SizedBox(width: AppSpacing.md),
              trailing!,
            ],
          );
        },
      ),
    );
  }
}
