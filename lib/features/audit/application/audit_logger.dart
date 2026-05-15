import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/utils/app_logger.dart';
import 'package:myapp/features/audit/data/audit_log_datasource.dart';
import 'package:myapp/features/audit/domain/audit_log_entry.dart';

/// Wrapper "fire-and-forget" para registrar eventos de auditoría desde los
/// notifiers. Nunca lanza ni bloquea el flujo principal: si la escritura
/// falla, se logea con AppLogger y seguimos.
class AuditLogger {
  const AuditLogger(this._dataSource);

  /// Constructor para tests / entornos sin Supabase. `log` se vuelve no-op
  /// y `myRecentEntries` devuelve una lista vacía.
  const AuditLogger.noop() : _dataSource = null;

  final AuditLogDataSource? _dataSource;

  Future<void> log(String event, {Map<String, dynamic>? metadata}) async {
    final ds = _dataSource;
    if (ds == null) return;
    try {
      await ds.insert(event: event, metadata: metadata);
    } catch (e) {
      AppLogger.w('AuditLogger.log($event) failed: $e');
    }
  }

  Future<List<AuditLogEntry>> myRecentEntries({int limit = 100}) async {
    final ds = _dataSource;
    if (ds == null) return const [];
    final rows = await ds.listMyEntries(limit: limit);
    return rows.map(AuditLogEntry.fromMap).toList(growable: false);
  }
}

final auditLogDataSourceProvider = Provider<AuditLogDataSource>((ref) {
  return AuditLogDataSource(ref.watch(supabaseClientProvider));
});

final auditLoggerProvider = Provider<AuditLogger>((ref) {
  return AuditLogger(ref.watch(auditLogDataSourceProvider));
});

/// Últimos eventos del usuario actual. Se recalcula al cambiar la sesión
/// (login/logout). `null` sin sesión.
final myAuditLogProvider =
    FutureProvider<List<AuditLogEntry>>((ref) async {
  final authed = ref.watch(isAuthenticatedProvider);
  if (!authed) return const [];
  return ref.watch(auditLoggerProvider).myRecentEntries();
});
