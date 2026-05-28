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

/// Flashcards de un temario (todas, ordenadas por fecha de repaso). Usado en
/// los contadores agregados del Studio (no en la pantalla de repaso).
final flashcardsProvider =
    FutureProvider.family<List<Flashcard>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listFlashcards(subjectId);
});

/// Preguntas del cuestionario de un temario (todas, contadores).
final quizQuestionsProvider =
    FutureProvider.family<List<QuizQuestion>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listQuizQuestions(subjectId);
});

/// Argumento "(temario, sección?)" para los providers con ámbito de sección.
/// `nodeId == null` significa "todo el temario" (vista agregada).
typedef SectionScope = ({String subjectId, String? nodeId});

/// Flashcards filtradas por sección (o todo el temario si `nodeId == null`).
/// Generación: siempre por sección activa. Visualización: ambas.
final flashcardsScopedProvider =
    FutureProvider.family<List<Flashcard>, SectionScope>((ref, s) {
  return ref
      .watch(subjectsDataSourceProvider)
      .listFlashcards(s.subjectId, nodeId: s.nodeId);
});

/// Preguntas del cuestionario filtradas por sección (o todo el temario).
final quizQuestionsScopedProvider =
    FutureProvider.family<List<QuizQuestion>, SectionScope>((ref, s) {
  return ref
      .watch(subjectsDataSourceProvider)
      .listQuizQuestions(s.subjectId, nodeId: s.nodeId);
});

/// Notas de TODO el temario (vista agregada "todas mis notas del temario").
/// La creación/edición sigue siendo por sección, como en `annotationsProvider`.
final annotationsForSubjectProvider =
    FutureProvider.family<List<Annotation>, String>((ref, subjectId) {
  return ref
      .watch(subjectsDataSourceProvider)
      .listAnnotationsForSubject(subjectId);
});

/// Banco de preguntas de examen de un temario (tests configurables).
final examQuestionsProvider =
    FutureProvider.family<List<QuizQuestion>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listExamQuestions(subjectId);
});

/// Banco GLOBAL de afirmaciones Verdadero/Falso del temario (mapeadas a nodo
/// por `content_hash`). Vacío si aún no se ha generado nada.
final tfQuestionsProvider =
    FutureProvider.family<List<TfQuestion>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listTfBank(subjectId);
});

/// Banco GLOBAL de preguntas a desarrollar del temario (mapeadas a nodo por
/// `content_hash`). Vacío si aún no se ha generado nada.
final essayQuestionsProvider =
    FutureProvider.family<List<EssayQuestion>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listEssayBank(subjectId);
});

/// Historial de tests realizados de un temario (recientes primero).
final examAttemptsProvider =
    FutureProvider.family<List<ExamAttempt>, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).listExamAttempts(subjectId);
});

/// Material reutilizable del temario contra la biblioteca global (por hash).
typedef SubjectMatch = ({
  int totalSections,
  int exact,
  int similar,
  int questions,
  int flashcards,
  int views,
  bool poor,
});

final subjectMatchProvider =
    FutureProvider.family<SubjectMatch, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).matchSubject(subjectId);
});

/// Guía de estudio cacheada de un temario (`null` si aún no se generó).
final studyGuideProvider =
    FutureProvider.family<String?, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).getStudyGuide(subjectId);
});

/// Chuleta "modo pánico" cacheada de un temario (`null` si aún no se generó).
final cramProvider = FutureProvider.family<String?, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).getCram(subjectId);
});

/// Racha de estudio: días consecutivos (terminando hoy o ayer) + el conjunto
/// de días estudiados ('yyyy-mm-dd') para un mini-calendario.
typedef StudyStreak = ({int current, Set<String> days});

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

final studyStreakProvider = FutureProvider<StudyStreak>((ref) async {
  final days = await ref.watch(subjectsDataSourceProvider).listStudyDays();
  final set = {for (final d in days) _ymd(d)};
  final today = DateTime.now();
  final t0 = DateTime(today.year, today.month, today.day);
  // La racha cuenta hacia atrás desde hoy; si hoy aún no estudió, desde ayer.
  var cursor = set.contains(_ymd(t0))
      ? t0
      : t0.subtract(const Duration(days: 1));
  var streak = 0;
  while (set.contains(_ymd(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return (current: streak, days: set);
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

/// Texto completo del temario (documento entero extraído), para mostrarlo al
/// seleccionar el nodo raíz del índice. `null` si aún no hay texto.
final subjectFullTextProvider =
    FutureProvider.family<String?, String>((ref, subjectId) {
  return ref.watch(subjectsDataSourceProvider).originalFullText(subjectId);
});
