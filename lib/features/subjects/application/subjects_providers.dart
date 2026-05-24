// ============================================================================
// subjects · Providers Riverpod (Fase 1)
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/subjects_datasource.dart';
import '../domain/subject.dart';

final subjectsDataSourceProvider = Provider<SubjectsDataSource>((ref) {
  return SubjectsDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de temarios del usuario.
final subjectsListProvider = FutureProvider<List<Subject>>((ref) {
  return ref.watch(subjectsDataSourceProvider).listSubjects();
});

/// Documentos de un temario concreto.
final subjectDocumentsProvider =
    FutureProvider.family<List<SubjectDocument>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listDocuments(subjectId);
});

/// Nodos del índice de un temario (lista plana; el árbol se arma en la UI).
final indexNodesProvider =
    FutureProvider.family<List<IndexNode>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listIndexNodes(subjectId);
});

/// IDs de los nodos del índice que ya tienen contenido IA (explicado/resumen),
/// para pintarlos en azul. Se invalida tras generar una vista.
final aiContentNodeIdsProvider =
    FutureProvider.family<Set<String>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listAiNodeIds(subjectId);
});

/// Notas del usuario de una sección del índice (por nodo).
final annotationsProvider =
    FutureProvider.family<List<Annotation>, String>((ref, nodeId) {
  return ref.watch(subjectsDataSourceProvider).listAnnotations(nodeId);
});

/// Flashcards de un temario (ordenadas por fecha de repaso).
final flashcardsProvider =
    FutureProvider.family<List<Flashcard>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listFlashcards(subjectId);
});

/// Clave (nodo, tipo de vista) para cachear contenido de nodo.
typedef NodeViewKey = ({String nodeId, String kind});

/// Vista cacheada de un nodo (`null` si aún no se generó).
final nodeContentProvider =
    FutureProvider.family<String?, NodeViewKey>((ref, key) {
  return ref.watch(subjectsDataSourceProvider).getNodeContent(
        key.nodeId,
        key.kind,
      );
});
