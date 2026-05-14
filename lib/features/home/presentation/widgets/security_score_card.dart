import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

/// Un punto de la checklist de seguridad: una etiqueta y si está cumplido.
class SecurityChecklistItem {
  const SecurityChecklistItem({required this.label, required this.done});

  final String label;
  final bool done;
}

/// Tarjeta de "puntuación de seguridad": un donut (fl_chart) con el % de
/// cobertura + la checklist de señales reales del usuario (email verificado,
/// 2FA, avatar, nombre). No es un dato inventado — sale del estado real de
/// la cuenta.
class SecurityScoreCard extends StatelessWidget {
  const SecurityScoreCard({
    required this.title,
    required this.items,
    super.key,
  });

  final String title;
  final List<SecurityChecklistItem> items;

  @override
  Widget build(BuildContext context) {
    final total = items.length;
    final done = items.where((i) => i.done).length;
    final percent = total == 0 ? 0 : (done * 100 / total).round();

    final accent = percent == 100
        ? context.colors.tertiary
        : context.colors.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 104,
                  height: 104,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 0,
                          centerSpaceRadius: 34,
                          startDegreeOffset: -90,
                          sections: [
                            PieChartSectionData(
                              value: done.toDouble(),
                              color: accent,
                              radius: 14,
                              showTitle: false,
                            ),
                            PieChartSectionData(
                              value: (total - done).toDouble(),
                              color: context.colors.surfaceContainerHighest,
                              radius: 14,
                              showTitle: false,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$percent%',
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(
                                item.done
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: item.done
                                    ? context.colors.tertiary
                                    : context.colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: context.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
