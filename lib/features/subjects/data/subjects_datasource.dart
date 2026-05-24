// ============================================================================
// subjects · Data layer (Fase 1)
// ----------------------------------------------------------------------------
// CRUD de temarios y documentos sobre Supabase (RLS por propietario). La subida
// va DIRECTA al bucket privado `temarios` (las policies por carpeta de usuario
// lo permiten); tras subir, se inserta la fila en `documents` y se dispara la
// Edge Function `ingest-document` que procesa el archivo por visión.
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/subject.dart';
import '../presentation/util/file_picker_web.dart';

class SubjectsException implements Exception {
  const SubjectsException(this.code, {this.detail});
  final String code;
  final String? detail;
  @override
  String toString() => 'SubjectsException($code)';
}

class SubjectsDataSource {
  const SubjectsDataSource(this._client);

  final SupabaseClient _client;

  static const String _bucket = 'temarios';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const SubjectsException('not_authenticated');
    return id;
  }

  Future<List<Subject>> listSubjects() async {
    final data = await _client
        .from('subjects')
        .select()
        .order('created_at', ascending: false);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Subject.fromMap)
        .toList(growable: false);
  }

  Future<Subject> createSubject(String title) async {
    final data = await _client
        .from('subjects')
        .insert({'user_id': _uid, 'title': title})
        .select()
        .single();
    return Subject.fromMap(data);
  }

  Future<void> deleteSubject(String id) async {
    await _client.from('subjects').delete().eq('id', id);
  }

  Future<List<SubjectDocument>> listDocuments(String subjectId) async {
    final data = await _client
        .from('documents')
        .select()
        .eq('subject_id', subjectId)
        .order('created_at');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(SubjectDocument.fromMap)
        .toList(growable: false);
  }

  /// Sube el archivo al bucket, registra el documento y dispara la ingesta.
  Future<void> uploadDocument({
    required String subjectId,
    required PickedFile file,
  }) async {
    final uid = _uid;
    final safeName = file.name.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    final path =
        '$uid/$subjectId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    try {
      await _client.storage.from(_bucket).uploadBinary(
            path,
            file.bytes,
            fileOptions: FileOptions(
              contentType: file.mimeType,
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      throw SubjectsException('upload_failed', detail: e.message);
    }

    final row = await _client
        .from('documents')
        .insert({
          'subject_id': subjectId,
          'user_id': uid,
          'storage_path': path,
          'file_name': file.name,
          'mime_type': file.mimeType,
          'size_bytes': file.bytes.length,
          'status': 'queued',
        })
        .select('id')
        .single();

    final documentId = row['id'] as String;

    // Dispara la ingesta. Si falla el trigger, el documento queda 'queued'
    // (se podrá reintentar); propagamos para que la UI avise.
    try {
      await _client.functions.invoke(
        'ingest-document',
        body: {'document_id': documentId},
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final code = (details is Map && details['error'] is String)
          ? details['error'] as String
          : 'ingest_trigger_failed';
      throw SubjectsException(code);
    }
  }

  Future<void> deleteDocument(SubjectDocument doc) async {
    // Borra primero el objeto de Storage (si falla, seguimos: la fila manda).
    try {
      await _client.storage.from(_bucket).remove([doc.storagePath]);
    } on StorageException catch (_) {
      // ignore: el objeto puede no existir; lo importante es borrar la fila.
    }
    await _client.from('documents').delete().eq('id', doc.id);
  }

  // ─────────────────── Índice + vistas (Fase 2) ───────────────────

  /// Dispara la generación del índice (EF en background; la UI hace polling
  /// de `subjects.index_status`).
  Future<void> generateIndex(String subjectId) async {
    try {
      await _client.functions.invoke(
        'generate-index',
        body: {'subject_id': subjectId},
      );
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  Future<List<IndexNode>> listIndexNodes(String subjectId) async {
    final data = await _client
        .from('index_nodes')
        .select()
        .eq('subject_id', subjectId)
        .order('depth')
        .order('position');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(IndexNode.fromMap)
        .toList(growable: false);
  }

  /// Valida (bloquea) el índice: una vez validado ya no se puede regenerar.
  /// RLS de subjects (propietario) permite el UPDATE desde el cliente.
  Future<void> validateIndex(String subjectId) async {
    await _client.from('subjects').update({
      'index_locked': true,
      'index_locked_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', subjectId);
  }

  /// IDs de los nodos que YA tienen contenido generado por IA (explicado o
  /// resumen), para marcarlos en el índice. RLS limita al usuario; los UUID de
  /// nodo son únicos, así que el árbol del temario los cruza sin ambigüedad.
  Future<Set<String>> listAiNodeIds(String subjectId) async {
    final data = await _client
        .from('node_content')
        .select('node_id')
        .neq('kind', 'original');
    return (data as List)
        .map((e) => (e as Map)['node_id'] as String)
        .toSet();
  }

  /// Lee la vista cacheada de un nodo (`null` si aún no se ha generado).
  Future<String?> getNodeContent(String nodeId, String kind) async {
    final data = await _client
        .from('node_content')
        .select('content')
        .eq('node_id', nodeId)
        .eq('kind', kind)
        .maybeSingle();
    if (data == null) return null;
    return data['content'] as String?;
  }

  /// Genera (o regenera con [force]) una vista de un nodo y devuelve el texto.
  Future<String> generateView({
    required String nodeId,
    required String kind,
    bool force = false,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'generate-views',
        body: {'node_id': nodeId, 'kind': kind, if (force) 'force': true},
      );
      final data = res.data;
      if (data is! Map) throw const SubjectsException('invalid_response');
      final p = data.cast<String, dynamic>();
      if (p['ok'] != true) {
        throw SubjectsException(
          (p['error'] as String?) ?? 'generation_failed',
          detail: p['detail'] as String?,
        );
      }
      return (p['content'] as String?) ?? '';
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  // ─────────────────── Notas / anotaciones (Fase 2) ───────────────────

  /// Notas de una sección del índice (más recientes primero).
  Future<List<Annotation>> listAnnotations(String nodeId) async {
    final data = await _client
        .from('annotations')
        .select()
        .eq('node_id', nodeId)
        .order('created_at', ascending: false);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Annotation.fromMap)
        .toList(growable: false);
  }

  /// Crea una nota en la sección [nodeId] del temario [subjectId].
  Future<Annotation> createAnnotation({
    required String subjectId,
    required String nodeId,
    required String body,
  }) async {
    final data = await _client
        .from('annotations')
        .insert({
          'subject_id': subjectId,
          'user_id': _uid,
          'node_id': nodeId,
          'body': body,
        })
        .select()
        .single();
    return Annotation.fromMap(data);
  }

  /// Actualiza el texto de una nota.
  Future<void> updateAnnotation(String id, String body) async {
    await _client.from('annotations').update({'body': body}).eq('id', id);
  }

  /// Borra una nota.
  Future<void> deleteAnnotation(String id) async {
    await _client.from('annotations').delete().eq('id', id);
  }

  // ─────────────────── Flashcards (Fase 3) ───────────────────

  /// Genera (vía EF) un lote de flashcards del temario o de una sección.
  /// Reemplaza el lote anterior del mismo ámbito. Devuelve cuántas creó.
  Future<int> generateFlashcards({
    required String subjectId,
    String? nodeId,
    int count = 12,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'generate-flashcards',
        body: {
          'subject_id': subjectId,
          if (nodeId != null) 'node_id': nodeId,
          'count': count,
        },
      );
      final data = res.data;
      if (data is! Map) throw const SubjectsException('invalid_response');
      final p = data.cast<String, dynamic>();
      if (p['ok'] != true) {
        throw SubjectsException(
          (p['error'] as String?) ?? 'generation_failed',
          detail: p['detail'] as String?,
        );
      }
      return (p['count'] as num?)?.toInt() ?? 0;
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  /// Flashcards del temario, ordenadas por fecha de repaso (lo que toca antes).
  Future<List<Flashcard>> listFlashcards(String subjectId) async {
    final data = await _client
        .from('flashcards')
        .select()
        .eq('subject_id', subjectId)
        .order('due_at');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Flashcard.fromMap)
        .toList(growable: false);
  }

  /// Aplica un repaso (SM-2 lite) y reprograma la tarjeta.
  Future<void> reviewFlashcard(Flashcard c, ReviewRating rating) async {
    final now = DateTime.now();
    var ease = c.ease;
    var reps = c.reps;
    var lapses = c.lapses;
    var interval = c.intervalDays;
    final DateTime due;
    switch (rating) {
      case ReviewRating.again:
        reps = 0;
        lapses += 1;
        interval = 0;
        ease = (ease - 0.2).clamp(1.3, 3.0);
        due = now.add(const Duration(minutes: 10));
      case ReviewRating.good:
        reps += 1;
        interval = reps <= 1 ? 1 : (reps == 2 ? 6 : (interval * ease).round());
        if (interval < 1) interval = 1;
        due = now.add(Duration(days: interval));
      case ReviewRating.easy:
        reps += 1;
        ease = (ease + 0.15).clamp(1.3, 3.0);
        final base = interval == 0 ? 1 : interval;
        interval = reps <= 1 ? 2 : (base * ease * 1.3).round();
        if (interval < 2) interval = 2;
        due = now.add(Duration(days: interval));
    }
    await _client.from('flashcards').update({
      'ease': ease,
      'interval_days': interval,
      'reps': reps,
      'lapses': lapses,
      'due_at': due.toUtc().toIso8601String(),
      'last_reviewed_at': now.toUtc().toIso8601String(),
    }).eq('id', c.id);
  }

  // ─────────────────── Cuestionario (Fase 3) ───────────────────

  /// Genera (vía EF) un cuestionario tipo test. Reemplaza el lote anterior del
  /// mismo ámbito. Devuelve cuántas preguntas creó.
  Future<int> generateQuiz({
    required String subjectId,
    String? nodeId,
    int count = 8,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'generate-quiz',
        body: {
          'subject_id': subjectId,
          if (nodeId != null) 'node_id': nodeId,
          'count': count,
        },
      );
      final data = res.data;
      if (data is! Map) throw const SubjectsException('invalid_response');
      final p = data.cast<String, dynamic>();
      if (p['ok'] != true) {
        throw SubjectsException(
          (p['error'] as String?) ?? 'generation_failed',
          detail: p['detail'] as String?,
        );
      }
      return (p['count'] as num?)?.toInt() ?? 0;
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  /// Preguntas del cuestionario de un temario.
  Future<List<QuizQuestion>> listQuizQuestions(String subjectId) async {
    final data = await _client
        .from('quiz_questions')
        .select()
        .eq('subject_id', subjectId)
        .order('created_at');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(QuizQuestion.fromMap)
        .toList(growable: false);
  }

  /// Registra el resultado de responder una pregunta (estadística de dominio).
  Future<void> recordQuizAnswer(QuizQuestion q, {required bool correct}) async {
    await _client.from('quiz_questions').update({
      'times_seen': q.timesSeen + 1,
      'times_correct': q.timesCorrect + (correct ? 1 : 0),
    }).eq('id', q.id);
  }

  // ─────────────────── Chat / preguntas a la IA (Fase 3) ───────────────────

  /// Historial del chat de un temario (cronológico).
  Future<List<({bool fromUser, String text})>> listChatMessages(
    String subjectId,
  ) async {
    final data = await _client
        .from('chat_messages')
        .select('role, content')
        .eq('subject_id', subjectId)
        .order('created_at');
    return (data as List)
        .map((e) {
          final m = e as Map;
          return (
            fromUser: (m['role'] as String?) == 'user',
            text: (m['content'] as String?) ?? '',
          );
        })
        .toList(growable: false);
  }

  /// Persiste un turno del chat.
  Future<void> addChatMessage({
    required String subjectId,
    required bool fromUser,
    required String content,
  }) async {
    await _client.from('chat_messages').insert({
      'subject_id': subjectId,
      'user_id': _uid,
      'role': fromUser ? 'user' : 'assistant',
      'content': content,
    });
  }

  /// Borra toda la conversación de un temario.
  Future<void> clearChatMessages(String subjectId) async {
    await _client.from('chat_messages').delete().eq('subject_id', subjectId);
  }

  /// Pregunta a la IA sobre el temario (o la sección [nodeId]). [history] son
  /// los turnos previos ({role:'user'|'assistant', content}). Devuelve la
  /// respuesta en texto (Markdown).
  Future<String> askSubject({
    required String subjectId,
    required String question,
    String? nodeId,
    List<Map<String, String>> history = const [],
  }) async {
    try {
      final res = await _client.functions.invoke(
        'ask-subject',
        body: {
          'subject_id': subjectId,
          if (nodeId != null) 'node_id': nodeId,
          'question': question,
          'history': history,
        },
      );
      final data = res.data;
      if (data is! Map) throw const SubjectsException('invalid_response');
      final p = data.cast<String, dynamic>();
      if (p['ok'] != true) {
        throw SubjectsException(
          (p['error'] as String?) ?? 'generation_failed',
          detail: p['detail'] as String?,
        );
      }
      return (p['answer'] as String?) ?? '';
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  /// URL firmada (1 h) del primer documento del temario, para abrir el
  /// original tal cual. `null` si no hay documentos.
  Future<String?> originalDocumentUrl(String subjectId) async {
    final rows = await _client
        .from('documents')
        .select('storage_path')
        .eq('subject_id', subjectId)
        .order('created_at')
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    final path = (list.first as Map)['storage_path'] as String;
    return _client.storage.from(_bucket).createSignedUrl(path, 3600);
  }

  String _efError(FunctionException e) {
    final d = e.details;
    if (d is Map && d['error'] is String) return d['error'] as String;
    return 'server_error';
  }
}
