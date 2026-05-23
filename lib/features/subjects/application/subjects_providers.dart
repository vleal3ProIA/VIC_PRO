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
