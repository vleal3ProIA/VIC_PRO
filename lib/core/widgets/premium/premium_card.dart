// ignore_for_file: always_put_required_named_parameters_first
// Razon: la convencion de Flutter es `super.key` primero (opcional)
// seguido de los parametros required. Este lint de very_good_analysis
// se contradice con la convencion oficial -- preferimos consistencia
// con el resto del codebase.

import 'package:flutter/material.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Card premium estilo Stripe / Linear / Notion. Sombra suave, border
/// sutil, esquinas redondeadas precisas, padding generoso.
///
/// **Diferencia con `Card` de Material**: Material `Card` usa
/// `elevation` que produce sombras "duras" estilo Material. Aqui
/// usamos sombras refinadas de `AppShadows.card` que se sienten mas
/// modernas (similar a Tailwind shadow-sm / shadow).
///
/// **Hover state**: opcional. Si `onTap` no es null, al pasar el cursor
/// (web/desktop) la card eleva ligeramente la sombra y aumenta el
/// border opacity. Animacion de 150ms.
///
/// **Uso tipico**:
/// ```dart
/// PremiumCard(
///   onTap: () => context.goNamed(RouteNames.invoices),
///   child: Column(
///     children: [
///       Text('Invoices', style: theme.textTheme.titleMedium),
///       Text('View your billing history'),
///     ],
///   ),
/// )
/// ```
///
/// **Responsive**: el padding por defecto es `AppSpacing.lg` (24px).
/// Para mobile compactar usar `padding: AppSpacing.paddingMd`.
class PremiumCard extends StatefulWidget {
  const PremiumCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.borderRadius,
    this.elevated = false,
    this.semanticLabel,
  });

  /// Contenido. Tipicamente un `Column` o `Row` con tu jerarquia visual.
  final Widget child;

  /// Si no es null, la card es clickable y muestra hover state.
  final VoidCallback? onTap;

  /// Padding interior. Default `AppSpacing.lg`. Para cards muy compactas
  /// usar `AppSpacing.paddingMd`.
  final EdgeInsetsGeometry padding;

  /// Radius custom. Default `AppRadii.card` (16px).
  final BorderRadius? borderRadius;

  /// `true` -> usa `AppShadows.elevated` en lugar de `AppShadows.card`.
  /// Util para cards "destacadas" (ej. plan recomendado, alerta).
  final bool elevated;

  /// Para a11y: lectores de pantalla anuncian este texto al focusar.
  /// Si la card es clickable, idealmente describe la accion ("Abrir
  /// configuracion de notificaciones").
  final String? semanticLabel;

  @override
  State<PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<PremiumCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final borderRadius = widget.borderRadius ?? AppRadii.brCard;
    final isInteractive = widget.onTap != null;

    // Sombras: estado normal vs hover (cuando interactivo).
    final shadows = widget.elevated
        ? AppShadows.elevated(theme.brightness)
        : AppShadows.card(theme.brightness);
    final hoverShadows = AppShadows.elevated(theme.brightness);

    // Fondo: usamos una capa más alta que `surface` (que es el fondo del
    // Scaffold) para que la card se diferencie SIEMPRE del fondo de la
    // página. En hover subimos otra capa para reforzar el feedback. Esto
    // hace que la card sea visible incluso si el border está apagado por
    // el lector OS o accesibilidad.
    final baseBg = scheme.surfaceContainerHigh;
    final hoverBg = scheme.surfaceContainerHighest;

    // Border más visible (antes 8-12% alpha → casi invisible sobre fondos
    // similares). Ahora 18-28% en light, 28-40% en dark, lo que da una
    // línea clara pero no agresiva (estilo Linear / Vercel / Notion).
    final baseBorderColor = isDark
        ? scheme.outline.withValues(alpha: 0.28)
        : scheme.outline.withValues(alpha: 0.18);
    final hoverBorderColor = isDark
        ? scheme.outline.withValues(alpha: 0.40)
        : scheme.outline.withValues(alpha: 0.28);

    final card = AnimatedContainer(
      duration: AppDurations.fast,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: (_hovered && isInteractive) ? hoverBg : baseBg,
        borderRadius: borderRadius,
        border: Border.all(
          color: (_hovered || _focused)
              ? hoverBorderColor
              : baseBorderColor,
          width: 1,
        ),
        boxShadow: (_hovered && isInteractive) ? hoverShadows : shadows,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _focused = f),
            // Solo aplicamos hover effect si es clickable.
            mouseCursor: isInteractive
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: Padding(
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    final wrapped = MouseRegion(
      onEnter: (_) => isInteractive ? setState(() => _hovered = true) : null,
      onExit: (_) => isInteractive ? setState(() => _hovered = false) : null,
      child: card,
    );

    if (widget.semanticLabel != null) {
      return Semantics(
        label: widget.semanticLabel,
        button: isInteractive,
        child: wrapped,
      );
    }
    return wrapped;
  }
}
