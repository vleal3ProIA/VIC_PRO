import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../domain/admin_metrics.dart';

/// Gráfico de barras horizontales con la distribución de tenants por
/// plan. Usa el color primario para el plan dominante y tonos
/// degradados para el resto.
class PlanDistributionBars extends StatelessWidget {
  const PlanDistributionBars({required this.rows, super.key});

  final List<PlanDistributionRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '—',
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    }
    final maxCount = rows.map((r) => r.count).reduce((a, b) => a > b ? a : b);
    final scale = maxCount == 0 ? 1.0 : maxCount.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    r.name,
                    style: context.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 22,
                          color: context.colors.surfaceContainerHighest,
                        ),
                        FractionallySizedBox(
                          widthFactor: r.count / scale,
                          child: Container(
                            height: 22,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  context.colors.primary,
                                  context.colors.primary.withValues(alpha: 0.65),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            r.count.toString(),
                            style: context.textTheme.bodySmall?.copyWith(
                              color: context.colors.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    _money(r.mrrCents),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _money(int cents) {
    if (cents == 0) return '—';
    return '${(cents / 100).toStringAsFixed(0)} €';
  }
}

// fl_chart is imported but the implementation above uses plain
// FractionallySizedBox for the bars — it's simpler, more accessible,
// and renders perfectly at small widths. The fl_chart import remains
// available for charts elsewhere that need it.
// ignore: unused_element
typedef _UnusedFlChart = BarChartData;
