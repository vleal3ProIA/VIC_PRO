import 'package:meta/meta.dart';

enum EmailLogStatus { queued, sent, failed }

EmailLogStatus _parseStatus(String? s) {
  switch (s) {
    case 'sent':
      return EmailLogStatus.sent;
    case 'failed':
      return EmailLogStatus.failed;
    default:
      return EmailLogStatus.queued;
  }
}

/// Una entrada en `email_log` — todo email saliente (auth, plan
/// changed, broadcasts) se registra aquí. Admin-only via RLS.
@immutable
class EmailLogEntry {
  const EmailLogEntry({
    required this.id,
    required this.type,
    required this.toEmail,
    required this.locale,
    required this.subject,
    required this.status,
    required this.provider,
    required this.meta,
    required this.createdAt,
    this.toUserId,
    this.error,
    this.sentAt,
  });

  factory EmailLogEntry.fromMap(Map<String, dynamic> m) {
    return EmailLogEntry(
      id: m['id'] as String,
      type: m['type'] as String,
      toEmail: m['to_email'] as String,
      toUserId: m['to_user_id'] as String?,
      locale: m['locale'] as String? ?? 'en',
      subject: m['subject'] as String? ?? '',
      status: _parseStatus(m['status'] as String?),
      error: m['error'] as String?,
      provider: m['provider'] as String? ?? 'smtp',
      meta: (m['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
      sentAt: m['sent_at'] != null
          ? DateTime.parse(m['sent_at'] as String)
          : null,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }

  final String id;
  final String type;
  final String toEmail;
  final String? toUserId;
  final String locale;
  final String subject;
  final EmailLogStatus status;
  final String? error;
  final String provider;
  final Map<String, dynamic> meta;
  final DateTime? sentAt;
  final DateTime createdAt;

  bool get isSent => status == EmailLogStatus.sent;
  bool get isFailed => status == EmailLogStatus.failed;
}
