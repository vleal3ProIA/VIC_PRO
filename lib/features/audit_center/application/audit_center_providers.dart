// ============================================================================
// Audit Center · Providers (PR-Audit-3)
// ----------------------------------------------------------------------------
// Providers Riverpod que exponen el datasource y los AsyncValue<...> de
// (a) lista de reports, (b) detalle de 1 report. El "trigger" de un
// nuevo audit es un imperativo (no un FutureProvider) -- lo gestiona la
// page con un boton + try/catch local.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/audit_center_datasource.dart';
import '../domain/audit_report.dart';

/// Singleton del datasource. Wireado al `SupabaseClient` global del app.
final auditCenterDataSourceProvider = Provider<AuditCenterDataSource>((ref) {
  return AuditCenterDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de reports recientes (sin findings detallados). La page la
/// invalida tras lanzar un audit nuevo o cuando el polling detecta que
/// un report 'running' cambio de estado.
final auditReportsListProvider =
    FutureProvider<List<AuditReportSummaryRow>>((ref) async {
  return ref.watch(auditCenterDataSourceProvider).listReports();
});

/// Detalle de un report concreto (con findings). `.family<String>` para
/// poder cachear por id sin colisionar entre detail pages distintas.
final auditReportDetailProvider =
    FutureProvider.family<AuditReport, String>((ref, id) async {
  return ref.watch(auditCenterDataSourceProvider).getReport(id);
});
