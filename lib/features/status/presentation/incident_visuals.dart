import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../domain/incident.dart';

/// Visuales para un valor de [IncidentStatus] (chip de estado).
({IconData icon, Color color, String Function(AppLocalizations) label})
incidentStatusVisuals(BuildContext context, IncidentStatus s) {
  switch (s) {
    case IncidentStatus.investigating:
      return (
        icon: Icons.search,
        color: Colors.amber.shade800,
        label: (l) => l.incidentStatusInvestigating,
      );
    case IncidentStatus.identified:
      return (
        icon: Icons.error_outline,
        color: Colors.orange.shade800,
        label: (l) => l.incidentStatusIdentified,
      );
    case IncidentStatus.monitoring:
      return (
        icon: Icons.monitor_heart_outlined,
        color: Colors.blue.shade700,
        label: (l) => l.incidentStatusMonitoring,
      );
    case IncidentStatus.resolved:
      return (
        icon: Icons.check_circle_outline,
        color: context.colors.primary,
        label: (l) => l.incidentStatusResolved,
      );
  }
}

/// Visuales para un valor de [IncidentSeverity] (chip de severidad
/// + color del banner in-app).
({IconData icon, Color color, String Function(AppLocalizations) label})
incidentSeverityVisuals(BuildContext context, IncidentSeverity s) {
  switch (s) {
    case IncidentSeverity.minor:
      return (
        icon: Icons.info_outline,
        color: Colors.amber.shade700,
        label: (l) => l.incidentSeverityMinor,
      );
    case IncidentSeverity.major:
      return (
        icon: Icons.warning_amber_outlined,
        color: Colors.orange.shade800,
        label: (l) => l.incidentSeverityMajor,
      );
    case IncidentSeverity.critical:
      return (
        icon: Icons.error_outline,
        color: context.colors.error,
        label: (l) => l.incidentSeverityCritical,
      );
    case IncidentSeverity.maintenance:
      return (
        icon: Icons.build_outlined,
        color: Colors.blue.shade700,
        label: (l) => l.incidentSeverityMaintenance,
      );
  }
}

/// Visuales del badge gigante del header de `/status` — el "overall"
/// que un visitante ve antes de leer cualquier detalle.
({IconData icon, Color color, String Function(AppLocalizations) label})
overallStatusVisuals(BuildContext context, OverallStatus s) {
  switch (s) {
    case OverallStatus.operational:
      return (
        icon: Icons.check_circle,
        color: context.colors.primary,
        label: (l) => l.statusOverallOperational,
      );
    case OverallStatus.degraded:
      return (
        icon: Icons.info,
        color: Colors.amber.shade700,
        label: (l) => l.statusOverallDegraded,
      );
    case OverallStatus.partialOutage:
      return (
        icon: Icons.warning_amber,
        color: Colors.orange.shade800,
        label: (l) => l.statusOverallPartialOutage,
      );
    case OverallStatus.majorOutage:
      return (
        icon: Icons.error,
        color: context.colors.error,
        label: (l) => l.statusOverallMajorOutage,
      );
    case OverallStatus.maintenance:
      return (
        icon: Icons.build,
        color: Colors.blue.shade700,
        label: (l) => l.statusOverallMaintenance,
      );
  }
}
