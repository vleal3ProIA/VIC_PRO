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

  String _efError(FunctionException e) {
    final d = e.details;
    if (d is Map && d['error'] is String) return d['error'] as String;
    return 'server_error';
  }
}
