// ============================================================================
// Audit Center · Chip de severity (PR-Audit-3)
// ----------------------------------------------------------------------------
// Wrapper de `PremiumBadge` con mapeo (AuditSeverity -> variant + label
// localizado). Lo usan la lista (pills compactas) y la detail page
// (headers de seccion).
//
// Tambien se usa con `count` para el patron `Critical 2`, `High 5`, etc.
// ============================================================================

import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/premium/premium_badge.dart';

import '../../domain/audit_report.dart';

class AuditSeverityChip extends StatelessWidget {
  const AuditSeverityChip({
    required this.severity,
    super.key,
    this.count,
    this.dense = false,
  });

  final AuditSeverity severity;

  /// Si `null` se muestra solo el label ("Critical"). Si numerico, el
  /// label es `Critical 3`.
  final int? count;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final labelBase = _label(context);
    final label = count != null ? '$labelBase $count' : labelBase;
    return PremiumBadge(
      label: label,
      variant: _variant(severity),
      dense: dense,
      icon: _icon(severity),
    );
  }

  String _label(BuildContext context) {
    final l = context.l10n;
    switch (severity) {
      case AuditSeverity.critical:
        return l.adminAuditSeverityCritical;
      case AuditSeverity.high:
        return l.adminAuditSeverityHigh;
      case AuditSeverity.medium:
        return l.adminAuditSeverityMedium;
      case AuditSeverity.low:
        return l.adminAuditSeverityLow;
      case AuditSeverity.info:
        return l.adminAuditSeverityInfo;
    }
  }

  PremiumBadgeVariant _variant(AuditSeverity s) {
    switch (s) {
      case AuditSeverity.critical:
      case AuditSeverity.high:
        return PremiumBadgeVariant.error;
      case AuditSeverity.medium:
        return PremiumBadgeVariant.warning;
      case AuditSeverity.low:
        return PremiumBadgeVariant.info;
      case AuditSeverity.info:
        return PremiumBadgeVariant.neutral;
    }
  }

  IconData? _icon(AuditSeverity s) {
    switch (s) {
      case AuditSeverity.critical:
        return Icons.error_rounded;
      case AuditSeverity.high:
        return Icons.warning_rounded;
      case AuditSeverity.medium:
        return Icons.report_problem_outlined;
      case AuditSeverity.low:
        return Icons.info_outline_rounded;
      case AuditSeverity.info:
        return Icons.lightbulb_outline_rounded;
    }
  }
}
