// ============================================================================
// subjects · Domain (Fase 1)
// ----------------------------------------------------------------------------
// Modelos de `subjects` (temarios) y `documents` (archivos subidos). Espejo de
// la migración 0051.
// ============================================================================

enum DocStatus { queued, processing, ready, failed }

DocStatus docStatusFrom(String? s) {
  switch (s) {
    case 'processing':
      return DocStatus.processing;
    case 'ready':
      return DocStatus.ready;
    case 'failed':
      return DocStatus.failed;
    default:
      return DocStatus.queued;
  }
}

class Subject {
  const Subject({
    required this.id,
    required this.title,
    this.language,
    this.createdAt,
  });

  factory Subject.fromMap(Map<String, dynamic> m) => Subject(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        language: m['language'] as String?,
        createdAt: _ts(m['created_at']),
      );

  final String id;
  final String title;
  final String? language;
  final DateTime? createdAt;
}

class SubjectDocument {
  const SubjectDocument({
    required this.id,
    required this.subjectId,
    required this.storagePath,
    required this.status,
    this.fileName,
    this.mimeType,
    this.pageCount,
    this.error,
  });

  factory SubjectDocument.fromMap(Map<String, dynamic> m) => SubjectDocument(
        id: m['id'] as String,
        subjectId: m['subject_id'] as String,
        storagePath: (m['storage_path'] as String?) ?? '',
        status: docStatusFrom(m['status'] as String?),
        fileName: m['file_name'] as String?,
        mimeType: m['mime_type'] as String?,
        pageCount: (m['page_count'] as num?)?.toInt(),
        error: m['error'] as String?,
      );

  final String id;
  final String subjectId;
  final String storagePath;
  final DocStatus status;
  final String? fileName;
  final String? mimeType;
  final int? pageCount;
  final String? error;

  /// `true` mientras el documento aún se está procesando (encolado o en curso).
  bool get inProgress =>
      status == DocStatus.queued || status == DocStatus.processing;
}

DateTime? _ts(Object? v) => v is String ? DateTime.tryParse(v) : null;
