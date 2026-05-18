// ignore_for_file: always_put_required_named_parameters_first
// Ver razonamiento en premium_card.dart.

import 'package:flutter/material.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Variantes semanticas de [PremiumBadge]. Cada una mapea a colores
/// que se interpretan automaticamente en el theme.
enum PremiumBadgeVariant {
  /// Verde -- estado positivo (active, paid, clean, success).
  success,

  /// Amarillo / amber -- estado de atencion (pending, warning, trial).
  warning,

  /// Rojo -- estado erroneo o destructivo (failed, deleted, blocked).
  error,

  /// Azul / primary -- estado informativo (new, info, beta).
  info,

  /// Gris -- estado neutro o inactivo (draft, archived, disabled).
  neutral,
}

/// Badge / chip pequenyo estilo Stripe / Linear. Padding compacto,
/// border radius pill (999) o sm (6) segun [pillShape], fondo
/// color-coded con opacity baja, texto del mismo color en bold.
///
/// Tres variantes:
/// - **Pill shape** (default): esquinas circulares totales. Estilo
///   Stripe metrics (`status: paid`).
/// - **Rounded** (`pillShape: false`): esquinas sm. Mas industrial,
///   estilo Linear issue labels.
///
/// **Iconos**: opcional `icon` a la izquierda del label. Tipicamente
/// puntos (`Icons.circle_rounded` size 8) o iconos pequenyos
/// (check, alert, info).
///
/// **Uso tipico**:
/// ```dart
/// PremiumBadge(
///   label: 'Active',
///   variant: PremiumBadgeVariant.success,
///   icon: Icons.check_circle_rounded,
/// )
///
/// PremiumBadge(
///   label: 'Pending review',
///   variant: PremiumBadgeVariant.warning,
///   pillShape: false,
/// )
/// ```
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({
    super.key,
    required this.label,
    this.variant = PremiumBadgeVariant.neutral,
    this.icon,
    this.pillShape = true,
    this.dense = false,
  });

  /// Texto del badge. Bold, color del variant.
  final String label;

  final PremiumBadgeVariant variant;

  /// Icono opcional a la izquierda. Tipicamente `Icons.circle_rounded`
  /// para dot status, o un icono pequenyo semantico.
  final IconData? icon;

  /// `true` (default) = esquinas circulares (pill). `false` = esquinas
  /// `AppRadii.sm` (industrial).
  final bool pillShape;

  /// `true` reduce el padding vertical y la fuente. Util en listas
  /// densas donde un badge full-size seria excesivo.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (fg, bg) = _resolveColors(scheme, variant);

    final hPad = dense ? 8.0 : 10.0;
    final vPad = dense ? 2.0 : 4.0;
    final fontSize = dense ? 11.0 : 12.0;
    final iconSize = dense ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius:
            pillShape ? AppRadii.brPill : AppRadii.brSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: fg),
            SizedBox(width: dense ? 4 : 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  /// Resuelve (foreground, background) segun variante y theme.
  /// Background siempre con opacity baja (~12-15%) para que el badge
  /// no compita con el texto principal del componente que lo aloja.
  (Color, Color) _resolveColors(
    ColorScheme scheme,
    PremiumBadgeVariant v,
  ) {
    switch (v) {
      case PremiumBadgeVariant.success:
        const c = Color(0xFF10B981); // emerald-500
        return (c, c.withValues(alpha: 0.12));
      case PremiumBadgeVariant.warning:
        const c = Color(0xFFF59E0B); // amber-500
        return (c, c.withValues(alpha: 0.12));
      case PremiumBadgeVariant.error:
        return (
          scheme.error,
          scheme.error.withValues(alpha: 0.12),
        );
      case PremiumBadgeVariant.info:
        return (
          scheme.primary,
          scheme.primary.withValues(alpha: 0.12),
        );
      case PremiumBadgeVariant.neutral:
        return (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        );
    }
  }
}
