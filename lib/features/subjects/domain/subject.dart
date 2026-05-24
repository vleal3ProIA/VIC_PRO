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

enum IndexStatus { none, generating, ready, failed }

IndexStatus indexStatusFrom(String? s) {
  switch (s) {
    case 'generating':
      return IndexStatus.generating;
    case 'ready':
      return IndexStatus.ready;
    case 'failed':
      return IndexStatus.failed;
    default:
      return IndexStatus.none;
  }
}

class Subject {
  const Subject({
    required this.id,
    required this.title,
    this.language,
    this.indexStatus = IndexStatus.none,
    this.createdAt,
  });

  factory Subject.fromMap(Map<String, dynamic> m) => Subject(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        language: m['language'] as String?,
        indexStatus: indexStatusFrom(m['index_status'] as String?),
        createdAt: _ts(m['created_at']),
      );

  final String id;
  final String title;
  final String? language;
  final IndexStatus indexStatus;
  final DateTime? createdAt;

  bool get indexGenerating => indexStatus == IndexStatus.generating;
  bool get indexReady => indexStatus == IndexStatus.ready;
}

/// Nodo del índice jerárquico (espejo de `index_nodes`).
class IndexNode {
  const IndexNode({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.position,
    required this.depth,
    this.parentId,
  });

  factory IndexNode.fromMap(Map<String, dynamic> m) => IndexNode(
        id: m['id'] as String,
        subjectId: m['subject_id'] as String,
        title: (m['title'] as String?) ?? '',
        position: (m['position'] as num?)?.toInt() ?? 0,
        depth: (m['depth'] as num?)?.toInt() ?? 0,
        parentId: m['parent_id'] as String?,
      );

  final String id;
  final String subjectId;
  final String title;
  final int position;
  final int depth;
  final String? parentId;
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
