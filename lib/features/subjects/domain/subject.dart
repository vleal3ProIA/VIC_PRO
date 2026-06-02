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
    this.indexLocked = false,
    this.indexError,
    this.examDate,
    this.createdAt,
    this.shareable = false,
  });

  factory Subject.fromMap(Map<String, dynamic> m) => Subject(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        language: m['language'] as String?,
        indexStatus: indexStatusFrom(m['index_status'] as String?),
        indexLocked: (m['index_locked'] as bool?) ?? false,
        indexError: m['index_error'] as String?,
        examDate: _ts(m['exam_date']),
        createdAt: _ts(m['created_at']),
        shareable: (m['shareable'] as bool?) ?? false,
      );

  final String id;
  final String title;
  final String? language;
  final IndexStatus indexStatus;

  /// `true` si el usuario declaró que este material es de fuente libre/pública
  /// y por tanto puede contribuir a la biblioteca global del proyecto.
  final bool shareable;

  /// Motivo del último fallo al generar el índice (`null` si no falló).
  final String? indexError;

  /// `true` cuando el usuario ha validado el índice: ya no se puede regenerar.
  final bool indexLocked;

  /// Fecha del examen (para la cuenta atrás y el ritmo de estudio).
  final DateTime? examDate;
  final DateTime? createdAt;

  /// Días que faltan para el examen (negativo si ya pasó, `null` si sin fecha).
  int? get daysToExam {
    final d = examDate;
    if (d == null) return null;
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final e0 = DateTime(d.year, d.month, d.day);
    return e0.difference(t0).inDays;
  }

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

/// Nota del usuario asociada a una sección del índice (espejo de `annotations`).
class Annotation {
  const Annotation({
    required this.id,
    required this.subjectId,
    required this.body,
    this.nodeId,
    this.createdAt,
    this.updatedAt,
  });

  factory Annotation.fromMap(Map<String, dynamic> m) => Annotation(
        id: m['id'] as String,
        subjectId: m['subject_id'] as String,
        body: (m['body'] as String?) ?? '',
        nodeId: m['node_id'] as String?,
        createdAt: _ts(m['created_at']),
        updatedAt: _ts(m['updated_at']),
      );

  final String id;
  final String subjectId;
  final String body;
  final String? nodeId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// Calificación de un repaso de flashcard (alimenta el repaso espaciado).
enum ReviewRating { again, good, easy }

/// Flashcard pregunta/respuesta con estado de repaso espaciado (SM-2 lite).
class Flashcard {
  const Flashcard({
    required this.id,
    required this.subjectId,
    required this.front,
    required this.back,
    this.nodeId,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.reps = 0,
    this.lapses = 0,
    this.dueAt,
  });

  factory Flashcard.fromMap(Map<String, dynamic> m) => Flashcard(
        id: m['id'] as String,
        subjectId: m['subject_id'] as String,
        front: (m['front'] as String?) ?? '',
        back: (m['back'] as String?) ?? '',
        nodeId: m['node_id'] as String?,
        ease: (m['ease'] as num?)?.toDouble() ?? 2.5,
        intervalDays: (m['interval_days'] as num?)?.toInt() ?? 0,
        reps: (m['reps'] as num?)?.toInt() ?? 0,
        lapses: (m['lapses'] as num?)?.toInt() ?? 0,
        dueAt: _ts(m['due_at']),
      );

  final String id;
  final String subjectId;
  final String front;
  final String back;
  final String? nodeId;
  final double ease;
  final int intervalDays;
  final int reps;
  final int lapses;
  final DateTime? dueAt;

  bool get isDue {
    final d = dueAt;
    return d == null || !d.isAfter(DateTime.now());
  }
}

/// Pregunta de opción múltiple del cuestionario / examen (espejo de
/// `quiz_questions` y `exam_questions`). En examen, `nodeId` indica la sección.
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.subjectId,
    required this.question,
    required this.options,
    required this.correctIndex,
    this.nodeId,
    this.explanation,
    this.timesSeen = 0,
    this.timesCorrect = 0,
  });

  factory QuizQuestion.fromMap(Map<String, dynamic> m) {
    final rawOpts = m['options'];
    final opts = rawOpts is List
        ? rawOpts.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return QuizQuestion(
      id: m['id'] as String,
      subjectId: m['subject_id'] as String,
      question: (m['question'] as String?) ?? '',
      options: opts,
      correctIndex: (m['correct_index'] as num?)?.toInt() ?? 0,
      nodeId: m['node_id'] as String?,
      explanation: m['explanation'] as String?,
      timesSeen: (m['times_seen'] as num?)?.toInt() ?? 0,
      timesCorrect: (m['times_correct'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String subjectId;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String? nodeId;
  final String? explanation;
  final int timesSeen;
  final int timesCorrect;
}

/// Afirmación Verdadero/Falso del banco GLOBAL `tf_bank` (Fase 4+). Misma idea
/// que [QuizQuestion] pero binaria. El `nodeId` solo se rellena cuando se
/// cruza el banco con `index_nodes.content_hash` para saber a qué sección del
/// temario pertenece (null si no se pudo mapear, p. ej. otro contenido).
class TfQuestion {
  const TfQuestion({
    required this.id,
    required this.statement,
    required this.isTrue,
    required this.explanation,
    required this.nodeId,
  });

  factory TfQuestion.fromMap(Map<String, dynamic> m, {String? nodeId}) {
    return TfQuestion(
      id: m['id'] as String,
      statement: (m['statement'] as String?) ?? '',
      isTrue: (m['is_true'] as bool?) ?? false,
      explanation: m['explanation'] as String?,
      nodeId: nodeId,
    );
  }

  final String id;
  final String statement;
  final bool isTrue;
  final String? explanation;

  /// Solo se rellena cuando se cruza el banco con `index_nodes.content_hash`
  /// para saber a qué sección pertenece. Null si no se pudo mapear.
  final String? nodeId;
}

/// Pregunta a desarrollar del banco GLOBAL `essay_bank` (Fase 4+). Contiene la
/// pregunta y su respuesta modelo (puede ser larga). El `nodeId` solo se
/// rellena cuando se cruza el banco con `index_nodes.content_hash` para saber
/// a qué sección del temario pertenece (null si no se pudo mapear).
class EssayQuestion {
  const EssayQuestion({
    required this.id,
    required this.question,
    required this.answer,
    required this.nodeId,
  });

  factory EssayQuestion.fromMap(Map<String, dynamic> m, {String? nodeId}) {
    return EssayQuestion(
      id: m['id'] as String,
      question: (m['question'] as String?) ?? '',
      answer: (m['answer'] as String?) ?? '',
      nodeId: nodeId,
    );
  }

  final String id;
  final String question;
  final String answer;

  /// Solo se rellena cuando se cruza el banco con `index_nodes.content_hash`
  /// para saber a qué sección pertenece. Null si no se pudo mapear.
  final String? nodeId;
}

/// Test PLANTILLA reutilizable: nombre, lista FIJA de question_ids (snapshot
/// del banco) y metadatos. El usuario lo realiza N veces; cada vez se crea un
/// [ExamAttempt] enlazado por [savedTestId]. Permite "repetir el mismo test",
/// ver el progreso a lo largo del tiempo, y combinar varios en uno nuevo.
class SavedTest {
  const SavedTest({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.questionIds,
    required this.nodeIds,
    required this.questionCount,
    required this.createdAt,
    this.updatedAt,
  });

  factory SavedTest.fromMap(Map<String, dynamic> m) {
    final rawQ = m['question_ids'];
    final qIds = rawQ is List
        ? rawQ.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    final rawN = m['node_ids'];
    final nIds = rawN is List
        ? rawN.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return SavedTest(
      id: m['id'] as String,
      subjectId: (m['subject_id'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      questionIds: qIds,
      nodeIds: nIds,
      questionCount: (m['question_count'] as num?)?.toInt() ?? qIds.length,
      createdAt:
          DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      updatedAt:
          DateTime.tryParse(m['updated_at']?.toString() ?? '')?.toLocal(),
    );
  }

  final String id;
  final String subjectId;
  final String title;
  final List<String> questionIds;
  final List<String> nodeIds;
  final int questionCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

/// Un test COMPLETADO (historial). Guarda nota, desglose, configuración y un
/// SNAPSHOT de las preguntas con la respuesta que marcó el usuario, para poder
/// revisarlo o repetirlo con las mismas preguntas y comparar la evolución.
///
/// Si [savedTestId] != null, el attempt es un intento de un [SavedTest]
/// concreto (permite agrupar intentos del mismo test, ver progreso, etc).
class ExamAttempt {
  const ExamAttempt({
    required this.id,
    required this.subjectId,
    required this.total,
    required this.answered,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.grade,
    required this.penalty,
    required this.timed,
    required this.minutes,
    required this.elapsedSeconds,
    required this.nodeIds,
    required this.questions,
    required this.answers,
    required this.createdAt,
    this.savedTestId,
  });

  factory ExamAttempt.fromMap(Map<String, dynamic> m) {
    final subjectId = (m['subject_id'] as String?) ?? '';
    final rawNodes = m['node_ids'];
    final nodeIds = rawNodes is List
        ? rawNodes.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    final rawQs = m['questions'];
    final questions = <QuizQuestion>[];
    final answers = <int?>[];
    if (rawQs is List) {
      for (final e in rawQs) {
        if (e is! Map) continue;
        final qm = e.cast<String, dynamic>();
        questions.add(QuizQuestion(
          id: (qm['id'] as String?) ?? '',
          subjectId: subjectId,
          question: (qm['question'] as String?) ?? '',
          options: qm['options'] is List
              ? (qm['options'] as List)
                  .map((o) => o.toString())
                  .toList(growable: false)
              : const <String>[],
          correctIndex: (qm['correct_index'] as num?)?.toInt() ?? 0,
          nodeId: qm['node_id'] as String?,
          explanation: qm['explanation'] as String?,
        ),);
        answers.add((qm['answer'] as num?)?.toInt());
      }
    }
    return ExamAttempt(
      id: m['id'] as String,
      subjectId: subjectId,
      total: (m['total'] as num?)?.toInt() ?? 0,
      answered: (m['answered'] as num?)?.toInt() ?? 0,
      correct: (m['correct'] as num?)?.toInt() ?? 0,
      wrong: (m['wrong'] as num?)?.toInt() ?? 0,
      blank: (m['blank'] as num?)?.toInt() ?? 0,
      grade: (m['grade'] as num?)?.toDouble() ?? 0,
      penalty: (m['penalty'] as bool?) ?? true,
      timed: (m['timed'] as bool?) ?? false,
      minutes: (m['minutes'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (m['elapsed_seconds'] as num?)?.toInt() ?? 0,
      nodeIds: nodeIds,
      questions: questions,
      answers: answers,
      createdAt:
          DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      savedTestId: m['saved_test_id'] as String?,
    );
  }

  final String id;
  final String subjectId;
  final int total;
  final int answered;
  final int correct;
  final int wrong;
  final int blank;
  final double grade;
  final bool penalty;
  final bool timed;
  final int minutes;
  final int elapsedSeconds;
  final List<String> nodeIds;
  final List<QuizQuestion> questions;
  final List<int?> answers;
  final DateTime createdAt;
  final String? savedTestId;
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
    this.sourceUrl,
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
        sourceUrl: m['source_url'] as String?,
      );

  final String id;
  final String subjectId;
  final String storagePath;
  final DocStatus status;
  final String? fileName;
  final String? mimeType;
  final int? pageCount;
  final String? error;

  /// URL publica de la que el user descargo el documento (BOE, gov,
  /// wikipedia, etc.). `null` si no se informo en la subida. Se usa para
  /// emparejar con la whitelist `public_domain_sources` y permitir al super
  /// admin descargar el original.
  final String? sourceUrl;

  /// `true` mientras el documento aún se está procesando (encolado o en curso).
  bool get inProgress =>
      status == DocStatus.queued || status == DocStatus.processing;
}

DateTime? _ts(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Fila de la RPC `admin_list_subjects` (super-admin only): subject + datos
/// del owner + contadores agregados (# docs, # secciones del indice). NO se
/// reusa [Subject] porque trae el owner desnormalizado para que la tabla del
/// Material Library no necesite N joins en el cliente.
class AdminSubjectRow {
  const AdminSubjectRow({
    required this.subject,
    required this.ownerUserId,
    required this.docsCount,
    required this.nodesCount,
    this.ownerEmail,
    this.ownerUsername,
    this.ownerDisplayName,
    this.isPublicDomain = false,
  });

  factory AdminSubjectRow.fromMap(Map<String, dynamic> m) => AdminSubjectRow(
        subject: Subject(
          id: m['id'] as String,
          title: (m['title'] as String?) ?? '',
          language: m['language'] as String?,
          indexStatus: indexStatusFrom(m['index_status'] as String?),
          indexLocked: (m['index_locked'] as bool?) ?? false,
          indexError: m['index_error'] as String?,
          examDate: _ts(m['exam_date']),
          createdAt: _ts(m['created_at']),
          shareable: (m['shareable'] as bool?) ?? false,
        ),
        ownerUserId: (m['user_id'] as String?) ?? '',
        ownerEmail: m['owner_email'] as String?,
        ownerUsername: m['owner_username'] as String?,
        ownerDisplayName: m['owner_display'] as String?,
        docsCount: (m['docs_count'] as num?)?.toInt() ?? 0,
        nodesCount: (m['nodes_count'] as num?)?.toInt() ?? 0,
        isPublicDomain: (m['is_public_domain'] as bool?) ?? false,
      );

  final Subject subject;
  final String ownerUserId;
  final String? ownerEmail;
  final String? ownerUsername;
  final String? ownerDisplayName;
  final int docsCount;
  final int nodesCount;

  /// `true` si el subject es shareable=true o alguno de sus documents tiene un
  /// `source_url` / `file_name` que casa con un pattern activo de
  /// `public_domain_sources`. Calculado server-side via la RPC
  /// `is_public_domain_subject`. Solo asi el super-admin podra descargar los
  /// documentos originales (RLS de storage lo verifica de nuevo).
  final bool isPublicDomain;

  /// Etiqueta amigable del owner: username > display_name > email > "—".
  String get ownerLabel {
    final u = ownerUsername;
    if (u != null && u.trim().isNotEmpty) return u;
    final d = ownerDisplayName;
    if (d != null && d.trim().isNotEmpty) return d;
    final e = ownerEmail;
    if (e != null && e.trim().isNotEmpty) return e;
    return '—';
  }
}

/// Fila de la RPC `admin_list_subject_owners` (autocomplete del filtro
/// owner en /admin/material-library).
class AdminOwnerRow {
  const AdminOwnerRow({
    required this.userId,
    required this.subjectsCount,
    this.email,
    this.username,
    this.displayName,
  });

  factory AdminOwnerRow.fromMap(Map<String, dynamic> m) => AdminOwnerRow(
        userId: (m['user_id'] as String?) ?? '',
        email: m['email'] as String?,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        subjectsCount: (m['subjects_count'] as num?)?.toInt() ?? 0,
      );

  final String userId;
  final String? email;
  final String? username;
  final String? displayName;
  final int subjectsCount;

  String get label {
    final u = username;
    if (u != null && u.trim().isNotEmpty) return u;
    final d = displayName;
    if (d != null && d.trim().isNotEmpty) return d;
    return email ?? userId;
  }
}
