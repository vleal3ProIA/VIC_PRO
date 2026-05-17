import 'package:meta/meta.dart';

/// Estado de un incidente — modela el ciclo Atlassian Statuspage.
enum IncidentStatus { investigating, identified, monitoring, resolved }

/// Severidad — gobierna si pintamos banner in-app y el "overall status"
/// global de la página `/status`.
enum IncidentSeverity { minor, major, critical, maintenance }

IncidentStatus _parseStatus(String? s) {
  switch (s) {
    case 'identified':
      return IncidentStatus.identified;
    case 'monitoring':
      return IncidentStatus.monitoring;
    case 'resolved':
      return IncidentStatus.resolved;
    default:
      return IncidentStatus.investigating;
  }
}

IncidentSeverity _parseSeverity(String? s) {
  switch (s) {
    case 'major':
      return IncidentSeverity.major;
    case 'critical':
      return IncidentSeverity.critical;
    case 'maintenance':
      return IncidentSeverity.maintenance;
    default:
      return IncidentSeverity.minor;
  }
}

String incidentStatusToDb(IncidentStatus s) {
  switch (s) {
    case IncidentStatus.investigating:
      return 'investigating';
    case IncidentStatus.identified:
      return 'identified';
    case IncidentStatus.monitoring:
      return 'monitoring';
    case IncidentStatus.resolved:
      return 'resolved';
  }
}

String incidentSeverityToDb(IncidentSeverity s) {
  switch (s) {
    case IncidentSeverity.minor:
      return 'minor';
    case IncidentSeverity.major:
      return 'major';
    case IncidentSeverity.critical:
      return 'critical';
    case IncidentSeverity.maintenance:
      return 'maintenance';
  }
}

@immutable
class Incident {
  const Incident({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.severity,
    required this.components,
    required this.startedAt,
    required this.published,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
  });

  factory Incident.fromMap(Map<String, dynamic> m) {
    return Incident(
      id: m['id'] as String,
      title: m['title'] as String,
      body: (m['body'] as String?) ?? '',
      status: _parseStatus(m['status'] as String?),
      severity: _parseSeverity(m['severity'] as String?),
      components: (m['components'] as List?)?.cast<String>() ?? const [],
      startedAt: DateTime.parse(m['started_at'] as String),
      resolvedAt: m['resolved_at'] != null
          ? DateTime.parse(m['resolved_at'] as String)
          : null,
      published: m['published'] as bool? ?? false,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }

  final String id;
  final String title;
  final String body;
  final IncidentStatus status;
  final IncidentSeverity severity;

  /// Servicios afectados (display only): 'api', 'auth', 'billing'...
  final List<String> components;

  final DateTime startedAt;
  final DateTime? resolvedAt;
  final bool published;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// `true` si está abierto (status != resolved). El trigger SQL
  /// mantiene `resolved_at` sincronizado con `status`.
  bool get isActive => status != IncidentStatus.resolved;
  bool get isResolved => status == IncidentStatus.resolved;

  /// `true` si merece banner in-app: severidad fuerte y aún activo.
  /// `minor` no pinta banner (lo verás solo si entras a /status).
  bool get warrantsBanner =>
      isActive &&
      (severity == IncidentSeverity.major ||
          severity == IncidentSeverity.critical ||
          severity == IncidentSeverity.maintenance);
}

/// Estado global de la app calculado a partir de los incidentes
/// activos. Determina el "big badge" del header de `/status`.
enum OverallStatus {
  operational,
  degraded,         // algún minor activo
  partialOutage,    // algún major activo
  majorOutage,      // algún critical activo
  maintenance,      // hay maintenance scheduled / en curso
}

OverallStatus computeOverallStatus(Iterable<Incident> activeIncidents) {
  var hasMaintenance = false;
  var hasMinor = false;
  var hasMajor = false;
  var hasCritical = false;
  for (final i in activeIncidents) {
    if (!i.isActive) continue;
    switch (i.severity) {
      case IncidentSeverity.critical:
        hasCritical = true;
      case IncidentSeverity.major:
        hasMajor = true;
      case IncidentSeverity.minor:
        hasMinor = true;
      case IncidentSeverity.maintenance:
        hasMaintenance = true;
    }
  }
  // Prioridad: critical > major > maintenance > minor > operational.
  // Maintenance se pinta por separado salvo que coincida con outage.
  if (hasCritical) return OverallStatus.majorOutage;
  if (hasMajor) return OverallStatus.partialOutage;
  if (hasMaintenance) return OverallStatus.maintenance;
  if (hasMinor) return OverallStatus.degraded;
  return OverallStatus.operational;
}
