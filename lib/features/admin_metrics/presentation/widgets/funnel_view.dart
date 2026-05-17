import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../domain/admin_metrics.dart';

/// Visualización del funnel: 4 barras descendentes con % de conversión
/// entre etapas. Apto para email-screenshot del CFO.
class FunnelView extends StatelessWidget {
  const FunnelView({required this.funnel, super.key});
  final MetricsFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final base = funnel.signups == 0 ? 1 : funnel.signups;
    final steps = [
      _FunnelStep(
        label: l.adminMetricsFunnelSignups,
        count: funnel.signups,
        widthFactor: 1,
      ),
      _FunnelStep(
        label: l.adminMetricsFunnelVerified,
        count: funnel.verified,
        widthFactor: funnel.verified / base,
      ),
      _FunnelStep(
        label: l.adminMetricsFunnelActiveSub,
        count: funnel.withActiveSub,
        widthFactor: funnel.withActiveSub / base,
      ),
      _FunnelStep(
        label: l.adminMetricsFunnelPaying,
        count: funnel.paying,
        widthFactor: funnel.paying / base,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _StepBar(
            step: steps[i],
            color: context.colors.primary.withValues(
              alpha: 1.0 - (i * 0.18),
            ),
          ),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.arrow_downward,
                    size: 14,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _pct(steps[i + 1].count, steps[i].count),
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _pct(int a, int b) {
    if (b == 0) return '—';
    final p = (a / b) * 100;
    return '${p.toStringAsFixed(1)}%';
  }
}

class _FunnelStep {
  const _FunnelStep({
    required this.label,
    required this.count,
    required this.widthFactor,
  });
  final String label;
  final int count;
  final double widthFactor;
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.color});
  final _FunnelStep step;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              step.label,
              style: context.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 30,
                    color: context.colors.surfaceContainerHighest,
                  ),
                  FractionallySizedBox(
                    widthFactor: step.widthFactor.clamp(0, 1).toDouble(),
                    child: Container(
                      height: 30,
                      decoration: BoxDecoration(color: color),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      step.count.toString(),
                      style: context.textTheme.titleSmall?.copyWith(
                        color: context.colors.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
