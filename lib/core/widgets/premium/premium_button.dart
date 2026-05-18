// ignore_for_file: always_put_required_named_parameters_first
// Ver razonamiento en premium_card.dart.

import 'package:flutter/material.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Variantes de [PremiumButton]. Cada una tiene su uso especifico --
/// elegirla mal degrada la jerarquia visual de la pantalla.
enum PremiumButtonVariant {
  /// Color primary del theme. Usar para la accion principal de un
  /// formulario o seccion. **MAX 1 por pantalla** (regla Stripe/Linear).
  primary,

  /// Fondo neutro con border sutil. Para acciones secundarias o
  /// alternativas (ej. "Cancelar" junto a un "Guardar" primary).
  secondary,

  /// Sin fondo, solo texto + color del theme. Para acciones tertiarias
  /// (ej. "Saltar", "Aprender mas"). El equivalente a un link estilizado.
  ghost,

  /// Variante destructiva: fondo rojo. Para borrar / revocar / eliminar.
  /// El user merece feedback visual fuerte antes de pulsarla.
  destructive,
}

/// Tamanyos de [PremiumButton]. Coherentes con la escala spacing del
/// proyecto. `md` es el default y cubre el 90% de casos.
enum PremiumButtonSize {
  /// Compact (36px alto). Para barras de herramientas o filtros.
  sm,

  /// Estandar (44px alto). Default. Toca a la regla Apple HIG de
  /// 44pt minimo touch target.
  md,

  /// Prominente (52px alto). Para CTAs grandes en landings o
  /// formularios destacados.
  lg,
}

/// Boton premium estilo Stripe / Linear / Notion. 4 variantes
/// (primary, secondary, ghost, destructive) y 3 tamanyos (sm, md, lg).
///
/// **Estados manejados**:
/// - Hover: ligera elevacion de sombra + cambio sutil de color.
/// - Pressed: scale down (-2%) + sombra reducida.
/// - Disabled: opacity reducida.
/// - Loading: spinner reemplaza al texto, sigue ocupando el mismo
///   ancho (no jumps).
///
/// **Iconos**: opcional prefix (`leadingIcon`) y suffix (`trailingIcon`).
/// Tipico: `Icons.add_rounded` en primary "Create", `Icons.arrow_forward`
/// en CTAs ("Continue ->").
///
/// **Full width**: por defecto el boton es intrinsic. Para uso en forms
/// donde quieres que ocupe todo el ancho de la columna, envuelve en
/// `SizedBox(width: double.infinity, child: PremiumButton(...))` o usa
/// el helper `fullWidth: true`.
///
/// **Uso**:
/// ```dart
/// PremiumButton(
///   label: 'Save changes',
///   variant: PremiumButtonVariant.primary,
///   leadingIcon: Icons.check_rounded,
///   onPressed: _onSave,
/// )
///
/// PremiumButton(
///   label: 'Delete account',
///   variant: PremiumButtonVariant.destructive,
///   onPressed: _showConfirm,
/// )
/// ```
class PremiumButton extends StatefulWidget {
  const PremiumButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PremiumButtonVariant.primary,
    this.size = PremiumButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.fullWidth = false,
    this.loading = false,
  });

  /// Texto del boton.
  final String label;

  /// Callback al pulsar. Si null -> boton disabled (no clickable, opacity
  /// reducida).
  final VoidCallback? onPressed;

  final PremiumButtonVariant variant;
  final PremiumButtonSize size;

  /// Icono opcional a la izquierda del label.
  final IconData? leadingIcon;

  /// Icono opcional a la derecha del label.
  final IconData? trailingIcon;

  /// Si true, el boton se estira al ancho del padre (`double.infinity`).
  final bool fullWidth;

  /// Si true, muestra spinner y se vuelve no-clickable.
  final bool loading;

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDisabled = widget.onPressed == null || widget.loading;

    final (height, hPad, fontSize, iconSize) = switch (widget.size) {
      PremiumButtonSize.sm => (36.0, 12.0, 13.0, 16.0),
      PremiumButtonSize.md => (44.0, 16.0, 14.0, 18.0),
      PremiumButtonSize.lg => (52.0, 20.0, 16.0, 20.0),
    };

    // Resolvemos colores segun variante.
    final colors = _resolveColors(scheme, widget.variant, isDisabled);

    // Sombra solo en primary/destructive cuando NO disabled.
    final hasShadow = !isDisabled &&
        (widget.variant == PremiumButtonVariant.primary ||
            widget.variant == PremiumButtonVariant.destructive);

    final button = AnimatedScale(
      duration: AppDurations.instant,
      scale: _pressed ? 0.98 : 1.0,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: Curves.easeOutCubic,
        height: height,
        decoration: BoxDecoration(
          color: _hovered && !isDisabled ? colors.hoverBg : colors.bg,
          borderRadius: AppRadii.brSm,
          border: colors.border != null
              ? Border.all(color: colors.border!)
              : null,
          boxShadow: hasShadow && !_pressed
              ? AppShadows.sm(theme.brightness)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isDisabled ? null : widget.onPressed,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: AppRadii.brSm,
            mouseCursor: isDisabled
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Row(
                mainAxisSize:
                    widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.loading)
                    SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colors.fg),
                      ),
                    )
                  else ...[
                    if (widget.leadingIcon != null) ...[
                      Icon(
                        widget.leadingIcon,
                        size: iconSize,
                        color: colors.fg,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.fg,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    if (widget.trailingIcon != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        widget.trailingIcon,
                        size: iconSize,
                        color: colors.fg,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final hovered = MouseRegion(
      onEnter: (_) =>
          !isDisabled ? setState(() => _hovered = true) : null,
      onExit: (_) =>
          !isDisabled ? setState(() => _hovered = false) : null,
      child: button,
    );

    if (widget.fullWidth) {
      return SizedBox(width: double.infinity, child: hovered);
    }
    return hovered;
  }

  _ButtonColors _resolveColors(
    ColorScheme scheme,
    PremiumButtonVariant variant,
    bool isDisabled,
  ) {
    final opacity = isDisabled ? 0.5 : 1.0;
    switch (variant) {
      case PremiumButtonVariant.primary:
        return _ButtonColors(
          bg: scheme.primary.withValues(alpha: opacity),
          hoverBg: scheme.primary.withValues(alpha: opacity * 0.92),
          fg: scheme.onPrimary,
          border: null,
        );
      case PremiumButtonVariant.secondary:
        return _ButtonColors(
          bg: scheme.surfaceContainerHighest.withValues(alpha: opacity),
          hoverBg:
              scheme.surfaceContainerHighest.withValues(alpha: opacity * 0.7),
          fg: scheme.onSurface.withValues(alpha: opacity),
          border: scheme.outline.withValues(alpha: 0.15),
        );
      case PremiumButtonVariant.ghost:
        return _ButtonColors(
          bg: Colors.transparent,
          hoverBg: scheme.onSurface.withValues(alpha: 0.06),
          fg: scheme.primary.withValues(alpha: opacity),
          border: null,
        );
      case PremiumButtonVariant.destructive:
        return _ButtonColors(
          bg: scheme.error.withValues(alpha: opacity),
          hoverBg: scheme.error.withValues(alpha: opacity * 0.9),
          fg: scheme.onError,
          border: null,
        );
    }
  }
}

class _ButtonColors {
  const _ButtonColors({
    required this.bg,
    required this.hoverBg,
    required this.fg,
    required this.border,
  });
  final Color bg;
  final Color hoverBg;
  final Color fg;
  final Color? border;
}
