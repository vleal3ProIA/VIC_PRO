// ignore_for_file: always_put_required_named_parameters_first
// Ver razonamiento en premium_card.dart.

import 'package:flutter/material.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Placeholder con efecto shimmer estilo Stripe / Linear / Notion para
/// mostrar mientras carga el contenido real. Sustituye al spinner
/// genérico de Material por algo más premium y predecible: el user ve
/// la forma del contenido que va a aparecer.
///
/// **Patron de uso**: en una pagina con datos async, mientras
/// `provider.isLoading`, renderizar un layout idéntico al final pero
/// con [SkeletonLoader] en cada slot:
///
/// ```dart
/// Column(
///   children: [
///     // Skeleton mientras carga, real cuando hay datos
///     async.when(
///       loading: () => Column(
///         children: [
///           SkeletonLoader(height: 32, width: 200),
///           AppSpacing.gapSm,
///           SkeletonLoader(height: 60, width: double.infinity),
///         ],
///       ),
///       data: (data) => MyRealUI(data),
///       error: (e, _) => MyErrorUI(),
///     ),
///   ],
/// )
/// ```
///
/// **Patron alternativo (helpers)**:
/// - [SkeletonLoader.text] -- linea de texto.
/// - [SkeletonLoader.circle] -- avatar circular.
/// - [SkeletonLoader.card] -- card completa con titulo + lineas.
///
/// **Animacion**: gradiente lineal que se desplaza de izq a der en
/// loop infinito. Duracion 1.5s (no demasiado rapido para no
/// distraer). En reduced-motion (a11y) la animacion se desactiva y
/// queda como un placeholder estatico.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    super.key,
    required this.height,
    this.width = double.infinity,
    this.borderRadius,
  });

  /// Linea de texto (height 16px). Default ancho 200.
  const SkeletonLoader.text({
    super.key,
    this.width = 200,
  })  : height = 16,
        borderRadius = AppRadii.brSm;

  /// Linea de texto compacta (height 12px). Para subtitulos / hints.
  const SkeletonLoader.textSmall({
    super.key,
    this.width = 140,
  })  : height = 12,
        borderRadius = AppRadii.brSm;

  /// Avatar circular (default 40px).
  const SkeletonLoader.circle({
    super.key,
    double size = 40,
  })  : height = size,
        width = size,
        borderRadius = AppRadii.brPill;

  /// Bloque rectangular grande (card placeholder).
  const SkeletonLoader.card({
    super.key,
    this.height = 120,
    this.width = double.infinity,
  }) : borderRadius = AppRadii.brMd;

  final double height;
  final double width;
  final BorderRadius? borderRadius;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Tonos del shimmer: base + highlight. En dark mode mas claros
    // respecto al fondo, en light mas oscuros.
    final baseColor = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.04);
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    // Respect reduced-motion: si el system pide reducir animaciones,
    // mostramos placeholder estatico.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: widget.borderRadius ?? AppRadii.brSm,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Posicion del gradiente segun el progress de la animacion:
        // de -1 (fuera izquierda) a 2 (fuera derecha).
        final t = _controller.value * 3 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? AppRadii.brSm,
            gradient: LinearGradient(
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
            ),
          ),
        );
      },
    );
  }

}
