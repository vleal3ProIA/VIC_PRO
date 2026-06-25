// ============================================================================
// subjects · Data layer (Fase 1)
// ----------------------------------------------------------------------------
// CRUD de temarios y documentos sobre Supabase (RLS por propietario). La subida
// va DIRECTA al bucket privado `temarios` (las policies por carpeta de usuario
// lo permiten); tras subir, se inserta la fila en `documents` y se dispara la
// Edge Function `ingest-document` que procesa el archivo por visión.
// ============================================================================

import 'dart:async';
import 'dart:convert';

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

  /// Lista los temarios del usuario actual ("Mis temarios"). Filtra
  /// explicitamente por `user_id` porque la policy `subjects_super_select`
  /// (migracion 0078) permite al super_admin leer TODOS los subjects para
  /// la vista `/admin/material-library`. Sin este filtro, el super_admin
  /// veria temarios ajenos mezclados en su panel personal.
  Future<List<Subject>> listSubjects() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final data = await _client
        .from('subjects')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Subject.fromMap)
        .toList(growable: false);
  }

  Future<Subject> createSubject(String title, {bool shareable = false}) async {
    final data = await _client
        .from('subjects')
        .insert({'user_id': _uid, 'title': title, 'shareable': shareable})
        .select()
        .single();
    return Subject.fromMap(data);
  }

  Future<void> deleteSubject(String id) async {
    await _client.from('subjects').delete().eq('id', id);
  }

  /// Renombra un temario (RLS de propietario permite el UPDATE desde el
  /// cliente). El [title] ya debe venir saneado/limitado desde la UI.
  Future<void> renameSubject(String id, String title) async {
    await _client.from('subjects').update({'title': title}).eq('id', id);
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
  ///
  /// [sourceUrl] es opcional: si el user la informa al subir (URL publica de
  /// la que descargo el archivo, p.ej. BOE / wikipedia), se persiste en
  /// `documents.source_url`. Sirve al super-admin para detectar material de
  /// dominio publico via la whitelist `public_domain_sources`.
  Future<void> uploadDocument({
    required String subjectId,
    required PickedFile file,
    String? sourceUrl,
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

    final cleanedSource =
        (sourceUrl == null || sourceUrl.trim().isEmpty) ? null : sourceUrl.trim();

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
          if (cleanedSource != null) 'source_url': cleanedSource,
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

  /// Resumen del material REUTILIZABLE del temario contra la biblioteca global
  /// (por `content_hash`, sin IA): secciones idénticas ya catalogadas, preguntas
  /// disponibles y explicaciones/resúmenes ya generados. Se reutiliza solo al
  /// abrir secciones o generar tests; aquí solo informamos.
  Future<
      ({
        int totalSections,
        int exact,
        int similar,
        int questions,
        int flashcards,
        int views,
        bool poor,
      })> matchSubject(String subjectId, {bool deep = false}) async {
    try {
      final res = await _client.functions.invoke(
        'match-subject',
        body: {'subject_id': subjectId, 'deep': deep},
      );
      final data = res.data;
      if (data is! Map) throw const SubjectsException('invalid_response');
      final p = data.cast<String, dynamic>();
      if (p['ok'] != true) {
        throw SubjectsException((p['error'] as String?) ?? 'match_failed');
      }
      return (
        totalSections: (p['totalSections'] as num?)?.toInt() ?? 0,
        exact: (p['exact'] as num?)?.toInt() ?? 0,
        similar: (p['similar'] as num?)?.toInt() ?? 0,
        questions: (p['questions'] as num?)?.toInt() ?? 0,
        flashcards: (p['flashcards'] as num?)?.toInt() ?? 0,
        views: (p['views'] as num?)?.toInt() ?? 0,
        poor: (p['poor'] as bool?) ?? false,
      );
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  /// Amplía un temario escaso con secciones de un temario similar más completo
  /// de la biblioteca global (vía EF `expand-subject`). Devuelve cuántas
  /// secciones se añadieron (0 si no había material adecuado).
  Future<int> expandSubject(String subjectId, {String? folderTitle}) async {
    try {
      final res = await _client.functions.invoke(
        'expand-subject',
        body: {
          'subject_id': subjectId,
          if (folderTitle != null) 'folder_title': folderTitle,
        },
      );
      final data = res.data;
      if (data is! Map) throw const SubjectsException('invalid_response');
      final p = data.cast<String, dynamic>();
      if (p['ok'] != true) {
        throw SubjectsException((p['error'] as String?) ?? 'expand_failed');
      }
      return (p['added'] as num?)?.toInt() ?? 0;
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  /// Valida (bloquea) el índice. Vía EF `validate-index`, que ADEMÁS contribuye
  /// el índice a la biblioteca global SOLO si el material es libre (así solo se
  /// cachean índices aprobados por el usuario). Si la EF fallara, caemos al
  /// UPDATE directo (RLS de propietario) para no bloquear la validación.
  Future<void> validateIndex(String subjectId) async {
    try {
      final res = await _client.functions.invoke(
        'validate-index',
        body: {'subject_id': subjectId},
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) return;
      throw const SubjectsException('validate_failed');
    } catch (_) {
      // Fallback: bloqueo directo (sin contribuir al pool).
      await _client.from('subjects').update({
        'index_locked': true,
        'index_locked_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', subjectId);
    }
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

  /// Notas de TODO el temario (vista global "ver mis notas del temario").
  /// Las notas se crean siempre asociadas a una sección, pero el usuario puede
  /// consultarlas todas a la vez.
  Future<List<Annotation>> listAnnotationsForSubject(String subjectId) async {
    final data = await _client
        .from('annotations')
        .select()
        .eq('subject_id', subjectId)
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
  /// Si se pasa [nodeId], solo devuelve las de esa sección activa; si no, las
  /// de TODO el temario (para la vista agregada "todo el temario").
  Future<List<Flashcard>> listFlashcards(
    String subjectId, {
    String? nodeId,
  }) async {
    var q = _client.from('flashcards').select().eq('subject_id', subjectId);
    if (nodeId != null) q = q.eq('node_id', nodeId);
    final data = await q.order('due_at');
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
    unawaited(recordStudyToday());
  }

  // ─────────────────── Actividad / racha (Fase 3) ───────────────────

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Marca "hoy" como día estudiado (idempotente). Best-effort, no bloquea.
  Future<void> recordStudyToday() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('study_activity').upsert(
        {'user_id': uid, 'day': _ymd(DateTime.now())},
        onConflict: 'user_id,day',
        ignoreDuplicates: true,
      );
    } catch (_) {
      // best-effort
    }
  }

  /// Días en los que el usuario estudió (recientes primero, máx 180).
  Future<List<DateTime>> listStudyDays() async {
    final data = await _client
        .from('study_activity')
        .select('day')
        .order('day', ascending: false)
        .limit(180);
    return (data as List)
        .map((e) => DateTime.tryParse((e as Map)['day'].toString()))
        .whereType<DateTime>()
        .toList(growable: false);
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

  /// Preguntas del cuestionario de un temario. Si se pasa [nodeId], solo
  /// devuelve las de esa sección activa (la generación es siempre por sección,
  /// pero la UI puede agregar las de todo el temario para la vista global).
  Future<List<QuizQuestion>> listQuizQuestions(
    String subjectId, {
    String? nodeId,
  }) async {
    var q = _client.from('quiz_questions').select().eq('subject_id', subjectId);
    if (nodeId != null) q = q.eq('node_id', nodeId);
    final data = await q.order('created_at');
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
    unawaited(recordStudyToday());
  }

  // ─────────────────── Test/examen configurable (Fase 4) ───────────────────

  /// Construye/extiende (vía EF) el banco de preguntas de las secciones
  /// [nodeIds] (vacío = todo el temario). Reutiliza lo ya guardado por
  /// contenido; solo llama a la IA para las secciones sin preguntas (o todas si
  /// [force]). Devuelve el progreso para informar al usuario.
  Future<({int generated, int reused, int pending, int total})> generateExam({
    required String subjectId,
    List<String> nodeIds = const [],
    bool force = false,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'generate-exam',
        body: {
          'subject_id': subjectId,
          'node_ids': nodeIds,
          'force': force,
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
      return (
        generated: (p['generated'] as num?)?.toInt() ?? 0,
        reused: (p['reused'] as num?)?.toInt() ?? 0,
        pending: (p['pending'] as num?)?.toInt() ?? 0,
        total: (p['total'] as num?)?.toInt() ?? 0,
      );
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  /// Banco de preguntas disponible para el temario: las del banco GLOBAL
  /// (`question_bank`) cuyo `content_hash` coincide con el de alguna sección del
  /// índice de este temario. Cada pregunta queda mapeada a su nodo.
  Future<List<QuizQuestion>> listExamQuestions(String subjectId) async {
    final nodesData = await _client
        .from('index_nodes')
        .select('id, content_hash')
        .eq('subject_id', subjectId);
    final hashToNode = <String, String>{};
    for (final n in (nodesData as List).cast<Map<String, dynamic>>()) {
      final h = n['content_hash'] as String?;
      if (h != null && h.isNotEmpty) {
        hashToNode.putIfAbsent(h, () => n['id'] as String);
      }
    }
    if (hashToNode.isEmpty) return const [];
    final hashes = hashToNode.keys.toList();
    final out = <QuizQuestion>[];
    for (var i = 0; i < hashes.length; i += 100) {
      final end = (i + 100) < hashes.length ? i + 100 : hashes.length;
      final chunk = hashes.sublist(i, end);
      final data = await _client
          .from('question_bank')
          .select()
          .inFilter('content_hash', chunk);
      for (final m in (data as List).cast<Map<String, dynamic>>()) {
        final h = m['content_hash'] as String?;
        final rawOpts = m['options'];
        out.add(
          QuizQuestion(
            id: m['id'] as String,
            subjectId: subjectId,
            question: (m['question'] as String?) ?? '',
            options: rawOpts is List
                ? rawOpts.map((e) => e.toString()).toList(growable: false)
                : const <String>[],
            correctIndex: (m['correct_index'] as num?)?.toInt() ?? 0,
            nodeId: h != null ? hashToNode[h] : null,
            explanation: m['explanation'] as String?,
          ),
        );
      }
    }
    return out;
  }

  // ─────────────────── Banco Verdadero/Falso (Fase 4+) ───────────────────

  /// Construye/extiende (vía EF `generate-tf`) el banco GLOBAL de afirmaciones
  /// V/F para las secciones [nodeIds] (vacío = todo el temario). Reutiliza lo
  /// ya guardado por contenido; solo llama a la IA para las secciones sin
  /// afirmaciones (o todas si [force]). Mismo shape de respuesta que
  /// [generateExam] (progreso por sección + total).
  Future<({int generated, int reused, int pending, int total})> generateTfBank({
    required String subjectId,
    List<String> nodeIds = const [],
    bool force = false,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'generate-tf',
        body: {
          'subject_id': subjectId,
          'node_ids': nodeIds,
          'force': force,
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
      return (
        generated: (p['generated'] as num?)?.toInt() ?? 0,
        reused: (p['reused'] as num?)?.toInt() ?? 0,
        pending: (p['pending'] as num?)?.toInt() ?? 0,
        total: (p['total'] as num?)?.toInt() ?? 0,
      );
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  /// Banco V/F disponible para el temario: las del banco GLOBAL `tf_bank` cuyo
  /// `content_hash` coincide con el de alguna sección del índice de este
  /// temario. Cada afirmación queda mapeada a su nodo (mismo patrón que
  /// [listExamQuestions]).
  Future<List<TfQuestion>> listTfBank(String subjectId) async {
    final nodesData = await _client
        .from('index_nodes')
        .select('id, content_hash')
        .eq('subject_id', subjectId);
    final hashToNode = <String, String>{};
    for (final n in (nodesData as List).cast<Map<String, dynamic>>()) {
      final h = n['content_hash'] as String?;
      if (h != null && h.isNotEmpty) {
        hashToNode.putIfAbsent(h, () => n['id'] as String);
      }
    }
    if (hashToNode.isEmpty) return const [];
    final hashes = hashToNode.keys.toList();
    final out = <TfQuestion>[];
    for (var i = 0; i < hashes.length; i += 100) {
      final end = (i + 100) < hashes.length ? i + 100 : hashes.length;
      final chunk = hashes.sublist(i, end);
      final data = await _client
          .from('tf_bank')
          .select()
          .inFilter('content_hash', chunk);
      for (final m in (data as List).cast<Map<String, dynamic>>()) {
        final h = m['content_hash'] as String?;
        out.add(TfQuestion.fromMap(m, nodeId: h != null ? hashToNode[h] : null));
      }
    }
    return out;
  }

  // ─────────────────── Banco preguntas a desarrollar (Fase 4+) ───────────────

  /// Construye/extiende (vía EF `generate-essay`) el banco GLOBAL de preguntas
  /// a desarrollar para las secciones [nodeIds] (vacío = todo el temario).
  /// Mismo shape de respuesta que [generateExam].
  Future<({int generated, int reused, int pending, int total})>
      generateEssayBank({
    required String subjectId,
    List<String> nodeIds = const [],
    bool force = false,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'generate-essay',
        body: {
          'subject_id': subjectId,
          'node_ids': nodeIds,
          'force': force,
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
      return (
        generated: (p['generated'] as num?)?.toInt() ?? 0,
        reused: (p['reused'] as num?)?.toInt() ?? 0,
        pending: (p['pending'] as num?)?.toInt() ?? 0,
        total: (p['total'] as num?)?.toInt() ?? 0,
      );
    } on FunctionException catch (e) {
      throw SubjectsException(_efError(e));
    }
  }

  /// Banco "desarrollo" disponible para el temario: las del banco GLOBAL
  /// `essay_bank` cuyo `content_hash` coincide con el de alguna sección del
  /// índice. Cada pregunta queda mapeada a su nodo.
  Future<List<EssayQuestion>> listEssayBank(String subjectId) async {
    final nodesData = await _client
        .from('index_nodes')
        .select('id, content_hash')
        .eq('subject_id', subjectId);
    final hashToNode = <String, String>{};
    for (final n in (nodesData as List).cast<Map<String, dynamic>>()) {
      final h = n['content_hash'] as String?;
      if (h != null && h.isNotEmpty) {
        hashToNode.putIfAbsent(h, () => n['id'] as String);
      }
    }
    if (hashToNode.isEmpty) return const [];
    final hashes = hashToNode.keys.toList();
    final out = <EssayQuestion>[];
    for (var i = 0; i < hashes.length; i += 100) {
      final end = (i + 100) < hashes.length ? i + 100 : hashes.length;
      final chunk = hashes.sublist(i, end);
      final data = await _client
          .from('essay_bank')
          .select()
          .inFilter('content_hash', chunk);
      for (final m in (data as List).cast<Map<String, dynamic>>()) {
        final h = m['content_hash'] as String?;
        out.add(
          EssayQuestion.fromMap(m, nodeId: h != null ? hashToNode[h] : null),
        );
      }
    }
    return out;
  }

  /// Guarda en el historial un test COMPLETADO (snapshot de preguntas +
  /// respuestas marcadas + desglose). Best-effort: no rompe el flujo del test.
  /// Si [savedTestId] != null, el attempt queda enlazado al test plantilla
  /// (permite agrupar intentos del mismo test, gráfica de evolución, etc.).
  Future<void> recordExamAttempt({
    required String subjectId,
    required List<QuizQuestion> questions,
    required List<int?> answers,
    required double grade,
    required bool penalty,
    required bool timed,
    required int minutes,
    required int elapsedSeconds,
    required List<String> nodeIds,
    String? savedTestId,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    var correct = 0;
    var wrong = 0;
    var blank = 0;
    final snapshot = <Map<String, dynamic>>[];
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final a = i < answers.length ? answers[i] : null;
      if (a == null) {
        blank++;
      } else if (a == q.correctIndex) {
        correct++;
      } else {
        wrong++;
      }
      snapshot.add({
        'id': q.id,
        'question': q.question,
        'options': q.options,
        'correct_index': q.correctIndex,
        'explanation': q.explanation,
        'node_id': q.nodeId,
        'answer': a,
      });
    }
    final total = questions.length;
    try {
      await _client.from('exam_attempts').insert({
        'subject_id': subjectId,
        'user_id': uid,
        'total': total,
        'answered': total - blank,
        'correct': correct,
        'wrong': wrong,
        'blank': blank,
        'grade': grade,
        'penalty': penalty,
        'timed': timed,
        'minutes': minutes,
        'elapsed_seconds': elapsedSeconds,
        'node_ids': nodeIds,
        'questions': snapshot,
        if (savedTestId != null) 'saved_test_id': savedTestId,
      });
    } catch (_) {
      // best-effort
    }
  }

  /// Historial de tests del temario (recientes primero, máx 100).
  Future<List<ExamAttempt>> listExamAttempts(String subjectId) async {
    final data = await _client
        .from('exam_attempts')
        .select()
        .eq('subject_id', subjectId)
        .order('created_at', ascending: false)
        .limit(100);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(ExamAttempt.fromMap)
        .toList(growable: false);
  }

  // ─────────────────────── Tests guardados (Fase F) ───────────────────────

  /// Crea un nuevo test plantilla con un snapshot de question_ids del banco
  /// correspondiente al [kind] (mock=question_bank, tf=tf_bank, essay=essay_bank).
  /// Devuelve el [SavedTest] persistido.
  Future<SavedTest> createSavedTest({
    required String subjectId,
    required String title,
    required List<String> questionIds,
    required List<String> nodeIds,
    SavedTestKind kind = SavedTestKind.mock,
  }) async {
    final uid = _uid;
    final data = await _client
        .from('saved_tests')
        .insert({
          'user_id': uid,
          'subject_id': subjectId,
          'title': title,
          'kind': kind.slug,
          'question_ids': questionIds,
          'node_ids': nodeIds,
          'question_count': questionIds.length,
        })
        .select()
        .single();
    return SavedTest.fromMap(data);
  }

  /// Lista de tests plantilla del temario filtrada por [kind]. Pagina con
  /// [limit] + [offset] para que la UI cargue por bloques (default: 50).
  /// Devuelve maximo 200 por llamada como safety cap.
  Future<List<SavedTest>> listSavedTests(
    String subjectId, {
    SavedTestKind kind = SavedTestKind.mock,
    int limit = 50,
    int offset = 0,
  }) async {
    final safe = limit.clamp(1, 200);
    final data = await _client
        .from('saved_tests')
        .select()
        .eq('subject_id', subjectId)
        .eq('kind', kind.slug)
        .order('created_at', ascending: false)
        .range(offset, offset + safe - 1);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(SavedTest.fromMap)
        .toList(growable: false);
  }

  /// Recupera un saved_test por id.
  Future<SavedTest?> getSavedTest(String id) async {
    final data =
        await _client.from('saved_tests').select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return SavedTest.fromMap(Map<String, dynamic>.from(data));
  }

  /// Renombra un saved_test.
  Future<void> renameSavedTest(String id, String title) async {
    await _client
        .from('saved_tests')
        .update({'title': title})
        .eq('id', id);
  }

  /// Borra un saved_test. Los `exam_attempts` enlazados quedan con
  /// `saved_test_id = NULL` (la FK tiene ON DELETE SET NULL).
  Future<void> deleteSavedTest(String id) async {
    await _client.from('saved_tests').delete().eq('id', id);
  }

  /// Combina varios saved_tests en uno nuevo via RPC. Devuelve el id del
  /// saved_test creado.
  Future<String> combineSavedTests({
    required List<String> sourceIds,
    required String title,
  }) async {
    final rpcRes = await _client.rpc<dynamic>(
      'combine_saved_tests',
      params: {
        'p_source_ids': sourceIds,
        'p_title': title,
      },
    );
    return rpcRes.toString();
  }

  /// Resuelve las preguntas (multi-choice) de un saved_test kind=mock.
  /// Las preguntas borradas del banco se omiten silenciosamente.
  Future<List<QuizQuestion>> getSavedTestQuestions(SavedTest s) async {
    if (s.questionIds.isEmpty) return const [];
    final out = <QuizQuestion>[];
    for (var i = 0; i < s.questionIds.length; i += 200) {
      final chunk = s.questionIds.sublist(
        i,
        i + 200 > s.questionIds.length ? s.questionIds.length : i + 200,
      );
      final data = await _client
          .from('question_bank')
          .select('id, content_hash, question, options, correct_index, explanation')
          .inFilter('id', chunk);
      final byId = <String, Map<String, dynamic>>{};
      for (final r in (data as List).cast<Map<String, dynamic>>()) {
        byId[r['id'] as String] = r;
      }
      for (final id in chunk) {
        final row = byId[id];
        if (row == null) continue;
        out.add(QuizQuestion(
          id: id,
          subjectId: s.subjectId,
          question: (row['question'] as String?) ?? '',
          options: row['options'] is List
              ? (row['options'] as List)
                  .map((e) => e.toString())
                  .toList(growable: false)
              : const <String>[],
          correctIndex: (row['correct_index'] as num?)?.toInt() ?? 0,
          explanation: row['explanation'] as String?,
        ),);
      }
    }
    return out;
  }

  /// Resuelve las afirmaciones V/F de un saved_test kind=tf.
  Future<List<TfQuestion>> getSavedTfTestQuestions(SavedTest s) async {
    if (s.questionIds.isEmpty) return const [];
    final out = <TfQuestion>[];
    for (var i = 0; i < s.questionIds.length; i += 200) {
      final chunk = s.questionIds.sublist(
        i,
        i + 200 > s.questionIds.length ? s.questionIds.length : i + 200,
      );
      final data = await _client
          .from('tf_bank')
          .select('id, content_hash, statement, is_true, explanation')
          .inFilter('id', chunk);
      final byId = <String, Map<String, dynamic>>{};
      for (final r in (data as List).cast<Map<String, dynamic>>()) {
        byId[r['id'] as String] = r;
      }
      for (final id in chunk) {
        final row = byId[id];
        if (row == null) continue;
        out.add(TfQuestion.fromMap(row));
      }
    }
    return out;
  }

  /// Resuelve las preguntas de desarrollo (ensayo) de un saved_test kind=essay.
  Future<List<EssayQuestion>> getSavedEssayTestQuestions(SavedTest s) async {
    if (s.questionIds.isEmpty) return const [];
    final out = <EssayQuestion>[];
    for (var i = 0; i < s.questionIds.length; i += 200) {
      final chunk = s.questionIds.sublist(
        i,
        i + 200 > s.questionIds.length ? s.questionIds.length : i + 200,
      );
      final data = await _client
          .from('essay_bank')
          .select('id, content_hash, question, answer')
          .inFilter('id', chunk);
      final byId = <String, Map<String, dynamic>>{};
      for (final r in (data as List).cast<Map<String, dynamic>>()) {
        byId[r['id'] as String] = r;
      }
      for (final id in chunk) {
        final row = byId[id];
        if (row == null) continue;
        out.add(EssayQuestion.fromMap(row));
      }
    }
    return out;
  }

  /// Attempts (intentos) realizados de un saved_test concreto, ordenados de
  /// más reciente a más antiguo. Para mostrar progreso y gráfica.
  Future<List<ExamAttempt>> listAttemptsForSavedTest(String savedTestId) async {
    final data = await _client
        .from('exam_attempts')
        .select()
        .eq('saved_test_id', savedTestId)
        .order('created_at', ascending: false)
        .limit(100);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(ExamAttempt.fromMap)
        .toList(growable: false);
  }

  // ─────────────────── Chat / preguntas a la IA (Fase 3) ───────────────────

  // ─────────────────── Examen: fecha + modo pánico (Fase 3) ───────────────────

  /// Fija (o limpia con `null`) la fecha de examen del temario.
  Future<void> setExamDate(String subjectId, DateTime? date) async {
    final iso = date == null
        ? null
        : '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
    await _client
        .from('subjects')
        .update({'exam_date': iso}).eq('id', subjectId);
  }

  /// Genera (vía EF) la chuleta "modo pánico" del temario y devuelve su texto.
  Future<String> generateCram(String subjectId) async {
    try {
      final res = await _client.functions.invoke(
        'generate-cram',
        body: {'subject_id': subjectId},
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

  /// Chuleta "modo pánico" cacheada (`null` si aún no se generó).
  Future<String?> getCram(String subjectId) async {
    final data = await _client
        .from('cram_sheets')
        .select('content')
        .eq('subject_id', subjectId)
        .maybeSingle();
    if (data == null) return null;
    return data['content'] as String?;
  }

  // ─────────────────── Guía de estudio (Fase 3) ───────────────────

  /// Genera (vía EF) la guía de estudio del temario y devuelve su contenido.
  Future<String> generateStudyGuide(String subjectId) async {
    try {
      final res = await _client.functions.invoke(
        'generate-study-guide',
        body: {'subject_id': subjectId},
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

  /// Guía de estudio cacheada del temario (`null` si aún no se generó).
  Future<String?> getStudyGuide(String subjectId) async {
    final data = await _client
        .from('study_guides')
        .select('content')
        .eq('subject_id', subjectId)
        .maybeSingle();
    if (data == null) return null;
    return data['content'] as String?;
  }

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

  /// Texto COMPLETO del temario (el extraído de los documentos 'ready',
  /// concatenado en orden). Es lo que mostramos al seleccionar el nodo raíz
  /// (título del temario): el documento entero tal cual su contenido. `null` si
  /// aún no hay texto extraído.
  Future<String?> originalFullText(String subjectId) async {
    final rows = await _client
        .from('documents')
        .select('extracted_text')
        .eq('subject_id', subjectId)
        .eq('status', 'ready')
        .order('created_at');
    final parts = (rows as List)
        .map((e) => (e as Map)['extracted_text'] as String?)
        .where((t) => t != null && t.trim().isNotEmpty)
        .map((t) => _plainTextFromExtracted(t!))
        .where((t) => t.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  /// Devuelve el texto legible de un `extracted_text`. Normalmente ya es texto
  /// plano, pero en datos antiguos podía haberse guardado como el JSON crudo del
  /// modelo (`{"language","title","text":"…\\n…"}`, a veces con fence ```json```).
  /// Si detecta ese caso y es parseable, extrae el campo `text` (con saltos de
  /// línea reales); si no, devuelve el original tal cual.
  static String _plainTextFromExtracted(String raw) {
    var t = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
    if (fence != null) t = (fence.group(1) ?? '').trim();
    if (t.startsWith('{') && t.endsWith('}')) {
      try {
        final obj = jsonDecode(t);
        if (obj is Map && obj['text'] is String) {
          final inner = (obj['text'] as String).trim();
          if (inner.isNotEmpty) return inner;
        }
      } catch (_) {
        // JSON inválido/truncado -> devolvemos el original.
      }
    }
    return raw;
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

  // ─────────────────── Admin Material Library (super-admin only) ──────────────
  //
  // Estos metodos hablan con las RPCs SECURITY DEFINER definidas en la
  // migracion 0078. RLS por owner se salta server-side, pero el gate
  // `is_super_admin()` rechaza a cualquiera que no sea el super con
  // `permission_denied`. Las funciones a continuacion ASUMEN que el caller
  // ya es super (la UI las protege con el guard de ruta).

  /// Lista TODOS los temarios del proyecto (no filtra por owner). Solo debe
  /// llamarse desde el panel admin -- la RPC rechaza a non-super con
  /// `permission_denied`. Soporta filtros + paginacion para no traer 10k
  /// filas al cliente.
  Future<List<AdminSubjectRow>> listAllSubjectsAdmin({
    String? language,
    String? ownerUserId,
    String? indexStatus,
    String? titleSearch,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 50,
    int offset = 0,
    bool onlyPublicDomain = false,
  }) async {
    final data = await _client.rpc<dynamic>(
      'admin_list_subjects',
      params: {
        'p_language': language,
        'p_owner_user_id': ownerUserId,
        'p_index_status': indexStatus,
        'p_title_search': titleSearch,
        'p_from_date': fromDate?.toUtc().toIso8601String(),
        'p_to_date': toDate?.toUtc().toIso8601String(),
        'p_limit': limit,
        'p_offset': offset,
        'p_only_public_domain': onlyPublicDomain,
      },
    );
    if (data is! List) return const [];
    return data
        .cast<Map<String, dynamic>>()
        .map(AdminSubjectRow.fromMap)
        .toList(growable: false);
  }

  /// URL firmada (1 h por defecto) para descargar un objeto concreto del
  /// bucket `temarios`. Solo funciona si la RLS de storage permite al
  /// caller leer ese objeto. Para super-admin con material de dominio
  /// publico, lo permite la policy `temarios_super_read_public_domain`
  /// (migracion 0079). Si el caller no tiene permiso, Storage devuelve
  /// 403 y este metodo propaga el error.
  Future<String> signedUrlForStoragePath(
    String storagePath, {
    int expiresInSeconds = 3600,
  }) {
    return _client.storage.from(_bucket).createSignedUrl(
          storagePath,
          expiresInSeconds,
        );
  }

  /// Autocomplete del filtro "owner" en /admin/material-library: busca en
  /// profiles.username, profiles.display_name y auth.users.email.
  Future<List<AdminOwnerRow>> listSubjectOwnersAdmin({
    String? search,
    int limit = 20,
  }) async {
    final data = await _client.rpc<dynamic>(
      'admin_list_subject_owners',
      params: {'p_search': search, 'p_limit': limit},
    );
    if (data is! List) return const [];
    return data
        .cast<Map<String, dynamic>>()
        .map(AdminOwnerRow.fromMap)
        .toList(growable: false);
  }

  /// Detalle read-only de un subject (salta RLS por owner). Devuelve null
  /// si no existe o si el caller no es super (la RPC ya tira en ese caso,
  /// asi que el null practicamente solo ocurre por id incorrecto).
  Future<AdminSubjectRow?> getSubjectAdmin(String subjectId) async {
    final data = await _client.rpc<dynamic>(
      'admin_get_subject',
      params: {'p_subject_id': subjectId},
    );
    if (data is! List || data.isEmpty) return null;
    return AdminSubjectRow.fromMap(
      (data.first as Map).cast<String, dynamic>(),
    );
  }

  // ─────────────────── "Resume last Panel" (migracion 0085) ────────────────
  // Persiste el ultimo Panel del user (subject + nodo) en profiles, para
  // que el siguiente login le devuelva directo a donde lo dejo.
  //
  // El call site (SubjectStudyPanel) lo llama fire-and-forget: si falla,
  // la UI no se entera (best-effort). La RPC valida ownership server-side
  // y hace silent ignore si el subject no es del caller (defensivo).

  /// Persiste el ultimo Panel del user (subject + nodo seleccionado). Si
  /// el subject no pertenece al user actual, la RPC silenciosamente no
  /// hace nada (no lanza). [nodeId] puede ser null si todavia no hay nodo
  /// seleccionado (acaba de abrir el Panel).
  Future<void> setLastPanel({
    required String subjectId,
    String? nodeId,
  }) async {
    await _client.rpc<dynamic>(
      'set_last_panel',
      params: {'p_subject_id': subjectId, 'p_node_id': nodeId},
    );
  }

  /// Lee el ultimo Panel (subject + nodo) del user actual desde `profiles`.
  /// Devuelve `(null, null)` si no hay sesion previa (user nuevo) o si el
  /// FK `on delete set null` ya limpio el subject (material borrado).
  ///
  /// Esta lectura va a la tabla profiles (RLS: `auth.uid() = id`), sin RPC,
  /// para que el provider `lastPanelLocationProvider` la pueda watch-ear
  /// con minimo overhead al cambiar el authState.
  Future<({String? subjectId, String? nodeId})> getLastPanel() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return (subjectId: null, nodeId: null);
    final data = await _client
        .from('profiles')
        .select('last_subject_id, last_node_id')
        .eq('id', uid)
        .maybeSingle();
    if (data == null) return (subjectId: null, nodeId: null);
    return (
      subjectId: data['last_subject_id'] as String?,
      nodeId: data['last_node_id'] as String?,
    );
  }
}
