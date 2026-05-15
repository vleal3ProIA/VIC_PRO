/// Una entrada del log de auditoría. Mapea una fila de `public.audit_logs`.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.event,
    required this.occurredAt,
    this.metadata,
  });

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id'] as String,
      event: map['event'] as String,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
    );
  }

  final String id;
  final String event;
  final DateTime occurredAt;
  final Map<String, dynamic>? metadata;
}
