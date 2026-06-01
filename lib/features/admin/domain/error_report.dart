// ============================================================================
// admin · domain/error_report.dart · Modelo del pipeline `/admin/errors`
// ----------------------------------------------------------------------------
// Mirror Dart de la tabla `public.error_reports` (migracion 0082) + el
// sub-modelo `AiDiagnosis` para el resultado cacheado de la EF
// `diagnose-error`.
// ============================================================================

import 'package:meta/meta.dart';

/// Severidad de un error (matchea el CHECK constraint).
enum ErrorReportSeverity {
  low,
  medium,
  high,
  critical;

  static ErrorReportSeverity fromString(String? raw) {
    switch (raw) {
      case 'low':
        return ErrorReportSeverity.low;
      case 'medium':
        return ErrorReportSeverity.medium;
      case 'high':
        return ErrorReportSeverity.high;
      case 'critical':
        return ErrorReportSeverity.critical;
      default:
        return ErrorReportSeverity.medium;
    }
  }

  /// Para ordenar (critical primero).
  int get rank => switch (this) {
        ErrorReportSeverity.critical => 0,
        ErrorReportSeverity.high => 1,
        ErrorReportSeverity.medium => 2,
        ErrorReportSeverity.low => 3,
      };
}

/// Estado del ciclo de vida.
enum ErrorReportStatus {
  open,
  inProgress,
  resolved,
  dismissed;

  static ErrorReportStatus fromString(String? raw) {
    switch (raw) {
      case 'open':
        return ErrorReportStatus.open;
      case 'in_progress':
        return ErrorReportStatus.inProgress;
      case 'resolved':
        return ErrorReportStatus.resolved;
      case 'dismissed':
        return ErrorReportStatus.dismissed;
      default:
        return ErrorReportStatus.open;
    }
  }

  /// Valor que viaja al backend (snake_case del CHECK).
  String get wire => switch (this) {
        ErrorReportStatus.open => 'open',
        ErrorReportStatus.inProgress => 'in_progress',
        ErrorReportStatus.resolved => 'resolved',
        ErrorReportStatus.dismissed => 'dismissed',
      };
}

/// Diagnostico IA cacheado del error. Coincide con el JSON que devuelve
/// la EF `diagnose-error`.
@immutable
class AiDiagnosis {
  const AiDiagnosis({
    required this.why,
    required this.whatUserDid,
    required this.howToFix,
  });

  factory AiDiagnosis.fromMap(Map<String, dynamic> m) {
    return AiDiagnosis(
      why: (m['why'] as String?)?.trim() ?? '',
      whatUserDid: (m['what_user_did'] as String?)?.trim() ?? '',
      howToFix: (m['how_to_fix'] as String?)?.trim() ?? '',
    );
  }

  final String why;
  final String whatUserDid;
  final String howToFix;

  bool get isComplete =>
      why.isNotEmpty && whatUserDid.isNotEmpty && howToFix.isNotEmpty;
}

/// Una fila de `error_reports`. La consumen tanto la lista como el detalle
/// (la lista solo lee algunos campos pero usa el mismo modelo, por consistencia).
@immutable
class ErrorReport {
  const ErrorReport({
    required this.id,
    required this.fn,
    required this.errorMessage,
    required this.severity,
    required this.status,
    required this.createdAt,
    this.userId,
    this.errorCode,
    this.errorDetails,
    this.context,
    this.resolutionNotes,
    this.aiDiagnosis,
    this.resolvedAt,
    this.resolvedBy,
  });

  factory ErrorReport.fromMap(Map<String, dynamic> m) {
    final ai = m['ai_diagnosis'];
    return ErrorReport(
      id: m['id'] as String,
      userId: m['user_id'] as String?,
      fn: (m['fn'] as String?) ?? '',
      errorCode: m['error_code'] as String?,
      errorMessage: (m['error_message'] as String?) ?? '',
      errorDetails: m['error_details'],
      context: m['context'],
      severity: ErrorReportSeverity.fromString(m['severity'] as String?),
      status: ErrorReportStatus.fromString(m['status'] as String?),
      resolutionNotes: m['resolution_notes'] as String?,
      aiDiagnosis: (ai is Map)
          ? AiDiagnosis.fromMap(ai.cast<String, dynamic>())
          : null,
      createdAt: DateTime.parse(m['created_at'] as String),
      resolvedAt: m['resolved_at'] != null
          ? DateTime.parse(m['resolved_at'] as String)
          : null,
      resolvedBy: m['resolved_by'] as String?,
    );
  }

  final String id;
  final String? userId;
  final String fn;
  final String? errorCode;
  final String errorMessage;

  /// jsonb libre (puede ser Map, List o primitivo). Lo mostramos como
  /// JSON pretty-printed en el detail.
  final Object? errorDetails;

  /// jsonb libre: typically `{ subject_id, node_id, kind, ... }`.
  final Object? context;

  final ErrorReportSeverity severity;
  final ErrorReportStatus status;
  final String? resolutionNotes;
  final AiDiagnosis? aiDiagnosis;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
}
