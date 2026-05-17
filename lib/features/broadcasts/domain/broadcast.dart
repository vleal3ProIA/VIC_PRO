import 'package:meta/meta.dart';

/// Audiencia del broadcast: tipo + valor dependiente del tipo.
enum BroadcastTargetType {
  all,
  plan,
  language,
  status;

  String get dbValue => name;
}

BroadcastTargetType _parseTargetType(String? s) {
  switch (s) {
    case 'plan':
      return BroadcastTargetType.plan;
    case 'language':
      return BroadcastTargetType.language;
    case 'status':
      return BroadcastTargetType.status;
    default:
      return BroadcastTargetType.all;
  }
}

enum BroadcastStatus { draft, sending, sent, failed }

BroadcastStatus _parseStatus(String? s) {
  switch (s) {
    case 'sending':
      return BroadcastStatus.sending;
    case 'sent':
      return BroadcastStatus.sent;
    case 'failed':
      return BroadcastStatus.failed;
    default:
      return BroadcastStatus.draft;
  }
}

@immutable
class Broadcast {
  const Broadcast({
    required this.id,
    required this.subject,
    required this.bodyHtml,
    required this.targetType,
    required this.targetValue,
    required this.status,
    required this.recipientsTotal,
    required this.sentCount,
    required this.failedCount,
    required this.processedOffset,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.finishedAt,
    this.lastError,
  });

  factory Broadcast.fromMap(Map<String, dynamic> m) {
    return Broadcast(
      id: m['id'] as String,
      subject: m['subject'] as String? ?? '',
      bodyHtml: m['body_html'] as String? ?? '',
      targetType: _parseTargetType(m['target_type'] as String?),
      targetValue:
          (m['target_value'] as Map?)?.cast<String, dynamic>() ?? const {},
      status: _parseStatus(m['status'] as String?),
      recipientsTotal: (m['recipients_total'] as num?)?.toInt() ?? 0,
      sentCount: (m['sent_count'] as num?)?.toInt() ?? 0,
      failedCount: (m['failed_count'] as num?)?.toInt() ?? 0,
      processedOffset: (m['processed_offset'] as num?)?.toInt() ?? 0,
      createdBy: m['created_by'] as String? ?? '',
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
      startedAt: m['started_at'] != null
          ? DateTime.parse(m['started_at'] as String)
          : null,
      finishedAt: m['finished_at'] != null
          ? DateTime.parse(m['finished_at'] as String)
          : null,
      lastError: m['last_error'] as String?,
    );
  }

  final String id;
  final String subject;
  final String bodyHtml;
  final BroadcastTargetType targetType;
  final Map<String, dynamic> targetValue;
  final BroadcastStatus status;
  final int recipientsTotal;
  final int sentCount;
  final int failedCount;
  final int processedOffset;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? lastError;

  /// `0..1` — fracción procesada del total.
  double get progressFraction {
    if (recipientsTotal == 0) return 0;
    return (processedOffset / recipientsTotal).clamp(0, 1).toDouble();
  }

  bool get isInFlight => status == BroadcastStatus.sending;
  bool get isFinished =>
      status == BroadcastStatus.sent || status == BroadcastStatus.failed;
}

/// Resultado de `admin_broadcast_estimate` — cuántos users recibirán
/// + cómo se distribuyen por locale.
@immutable
class BroadcastEstimate {
  const BroadcastEstimate({required this.count, required this.byLocale});

  factory BroadcastEstimate.fromMap(Map<String, dynamic> m) {
    final byLocaleRaw =
        (m['by_locale'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BroadcastEstimate(
      count: (m['count'] as num?)?.toInt() ?? 0,
      byLocale: byLocaleRaw.map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      ),
    );
  }

  final int count;
  final Map<String, int> byLocale;
}
