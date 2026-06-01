// ============================================================================
// admin · application/error_reports_providers.dart
// ----------------------------------------------------------------------------
// Providers Riverpod del pipeline `/admin/errors`. Cacheados por filtro
// (status+severity) en la lista, y por id en el detail.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/error_reports_datasource.dart';
import '../domain/error_report.dart';

final errorReportsDataSourceProvider =
    Provider<ErrorReportsDataSource>((ref) {
  return ErrorReportsDataSource(ref.watch(supabaseClientProvider));
});

/// Filtros activos en la lista. Inmutable. La UI los muta v.ia
/// `ref.read(errorReportsFilterProvider.notifier).state = ...`.
class ErrorReportsFilter {
  const ErrorReportsFilter({this.status, this.severity});
  final ErrorReportStatus? status;
  final ErrorReportSeverity? severity;
}

final errorReportsFilterProvider = StateProvider<ErrorReportsFilter>(
  // Por defecto, abiertas. El admin ve lo accionable primero.
  (ref) => const ErrorReportsFilter(status: ErrorReportStatus.open),
);

final errorReportsListProvider =
    FutureProvider<List<ErrorReport>>((ref) async {
  final filter = ref.watch(errorReportsFilterProvider);
  return ref.watch(errorReportsDataSourceProvider).list(
        status: filter.status,
        severity: filter.severity,
      );
});

/// Detalle de un report concreto.
final errorReportProvider =
    FutureProvider.family<ErrorReport?, String>((ref, id) async {
  return ref.watch(errorReportsDataSourceProvider).get(id);
});
