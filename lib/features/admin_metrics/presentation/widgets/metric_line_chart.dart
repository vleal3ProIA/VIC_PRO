import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../domain/admin_metrics.dart';

/// Gráfico de líneas reutilizable para una serie temporal. Diseñado
/// para ser plug-and-play: le pasas los puntos + un formateador del
/// valor (ej. "10.5€" o "12 users") y se encarga del resto.
///
/// Decisiones visuales:
///   - Línea con color primario, área debajo suave (gradient alpha).
///   - Tooltip al hover con fecha + valor formateado.
///   - Etiquetas X cada N puntos según el rango (legible sin amontonar).
///   - Auto-scale del eje Y con paddings sensatos.
class MetricLineChart extends StatelessWidget {
  const MetricLineChart({
    required this.points,
    required this.formatValue,
    required this.semanticsLabel,
    this.color,
    super.key,
  });

  final List<MetricPoint> points;
  final String Function(double value) formatValue;
  final String semanticsLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    final localeCode = Localizations.localeOf(context).languageCode;
    final dateFmt = DateFormat.MMMd(localeCode);

    if (points.isEmpty) {
      return Center(
        child: Text(
          '—',
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    }

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];

    // Eje Y: 4 ticks bien repartidos. Si todos los valores son 0,
    // dejamos un rango [0,1] para que el grid no colapse.
    final maxY = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final yMax = maxY <= 0 ? 1.0 : (maxY * 1.15);

    // Eje X: mostramos ~6 etiquetas como máximo (cabecera/tail + intermedios)
    final xLabelEvery = (points.length / 6).ceil().clamp(1, 1000);

    return Semantics(
      label: semanticsLabel,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: yMax,
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yMax / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: context.colors.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: yMax / 4,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    formatValue(value),
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  if (i % xLabelEvery != 0 && i != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      dateFmt.format(points[i].day),
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) =>
                  context.colors.inverseSurface.withValues(alpha: 0.92),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((s) {
                  final i = s.x.toInt();
                  if (i < 0 || i >= points.length) return null;
                  final p = points[i];
                  return LineTooltipItem(
                    '${dateFmt.format(p.day)}\n${formatValue(p.value)}',
                    TextStyle(
                      color: context.colors.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: c,
              barWidth: 2.5,
              isCurved: true,
              curveSmoothness: 0.18,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.withValues(alpha: 0.25),
                    c.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
