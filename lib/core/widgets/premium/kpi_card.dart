// ignore_for_file: always_put_required_named_parameters_first
// Ver razonamiento en premium_card.dart.

import 'package:flutter/material.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/premium/premium_card.dart';

/// Tarjeta KPI estilo Stripe / Linear: icono color-accented arriba +
/// valor grande en bold + label descriptiva debajo. Opcional: trend
/// indicator (+12% vs last month, estilo Stripe metrics).
///
/// Usada tipicamente en grids de dashboard (`Wrap` con
/// `runSpacing: AppSpacing.md`).
///
/// **Variantes**:
/// - Sin trend -> card simple con valor y label.
/// - Con `trend` -> agrega pill arriba derecha con delta + color
///   (verde positivo / rojo negativo / neutro gris).
///
/// **Responsive**: ancho minimo 240px. En mobile usar 1 card per row;
/// en tablet 2; en desktop 4. Gestionar desde el Wrap padre.
///
/// **Uso**:
/// ```dart
/// KpiCard(
///   icon: Icons.attach_money_outlined,
///   iconColor: Colors.green,
///   value: '\$3,249',
///   label: 'Total Revenue',
///   trend: KpiTrend(delta: 12.5, isPositive: true),
/// )
/// ```
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor,
    this.trend,
    this.onTap,
    this.semanticLabel,
  });

  /// Icono outlined (Material icons). Default color = primary del theme.
  final IconData icon;

  /// Color del icono. Default = `theme.colorScheme.primary`.
  final Color? iconColor;

  /// Valor grande (ej. `'$3,249'`, `'1.2K'`, `'87%'`). Bold.
  final String value;

  /// Label descriptivo abajo (ej. `'Total Revenue'`).
  final String label;

  /// Indicador opcional de tendencia. Default: no se muestra.
  final KpiTrend? trend;

  /// Si no null, la card es clickable (heredado de PremiumCard).
  final VoidCallback? onTap;

  /// A11y label.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resolvedIconColor = iconColor ?? scheme.primary;

    // Fondo del avatar del icono: 12% del color para dar identidad sin
    // sobresaturar.
    final iconBgColor = resolvedIconColor.withValues(alpha: 0.12);

    return PremiumCard(
      onTap: onTap,
      semanticLabel: semanticLabel ?? '$label: $value',
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fila superior: icono + (opcional) trend pill.
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: AppRadii.brMd,
                ),
                child: Icon(icon, color: resolvedIconColor, size: 22),
              ),
              const Spacer(),
              if (trend != null) _TrendPill(trend: trend!),
            ],
          ),
          AppSpacing.gapMd,
          // Valor grande.
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          AppSpacing.gapXs,
          // Label.
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Datos de tendencia para el pill superior derecho de [KpiCard].
class KpiTrend {
  const KpiTrend({
    required this.delta,
    required this.isPositive,
    this.suffix = '%',
  });

  /// Valor absoluto del cambio (ej. 12.5). NO uses negativos -- usa
  /// `isPositive: false`.
  final double delta;

  /// Si true -> pill verde con flecha arriba; false -> rojo con flecha
  /// abajo. Casos "neutros" (delta = 0) renderizar como positivo en gris.
  final bool isPositive;

  /// Sufijo del valor. Default `%`. Para "+12 vs ayer" pasar `''`.
  final String suffix;
}

class _TrendPill extends StatelessWidget {
  const _TrendPill({required this.trend});
  final KpiTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPositive = trend.isPositive;
    final color = isPositive
        ? const Color(0xFF10B981) // emerald-500
        : const Color(0xFFEF4444); // red-500
    final bgColor = color.withValues(alpha: 0.12);
    final icon = isPositive
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;
    // Si delta == 0, neutralizamos a gris (no muestra direccion).
    final isNeutral = trend.delta == 0;
    final effectiveColor = isNeutral ? scheme.onSurfaceVariant : color;
    final effectiveBg = isNeutral
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : bgColor;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: AppRadii.brPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isNeutral) ...[
            Icon(icon, size: 12, color: effectiveColor),
            const SizedBox(width: 2),
          ],
          Text(
            '${trend.delta.toStringAsFixed(trend.delta % 1 == 0 ? 0 : 1)}${trend.suffix}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: effectiveColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
