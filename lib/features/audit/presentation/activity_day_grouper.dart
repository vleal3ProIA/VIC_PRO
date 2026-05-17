import 'package:intl/intl.dart';
import 'package:myapp/features/audit/domain/audit_log_entry.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

/// Un grupo de entries que ocurrieron el mismo día. La pantalla
/// `/activity` usa esto para pintar headers tipo "Hoy", "Ayer",
/// "Hace 3 días", "15 de mayo", etc.
class ActivityDayGroup {
  ActivityDayGroup({required this.label, required this.entries});

  /// Texto del header del grupo, ya localizado y relativo.
  final String label;

  /// Entries dentro del grupo, ordenadas igual que la lista original
  /// (típicamente desc por tiempo).
  final List<AuditLogEntry> entries;
}

/// Agrupa [entries] por día (zona horaria local) y devuelve una lista
/// de grupos con label relativo. Conserva el orden cronológico
/// descendente (los grupos más recientes primero).
///
/// Labels que produce:
/// - "Hoy" / "Today" para el día actual
/// - "Ayer" / "Yesterday" para el anterior
/// - "Hace N días" (2..6 días)
/// - Fecha localizada `DateFormat.yMMMMd` para >6 días
List<ActivityDayGroup> groupByDay(
  List<AuditLogEntry> entries,
  AppLocalizations l,
  String localeCode,
) {
  if (entries.isEmpty) return const [];
  final groups = <DateTime, List<AuditLogEntry>>{};
  for (final e in entries) {
    final local = e.occurredAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    groups.putIfAbsent(day, () => []).add(e);
  }
  // Ordenar grupos desc por fecha.
  final sortedKeys = groups.keys.toList()
    ..sort((a, b) => b.compareTo(a));

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final formatter = DateFormat.yMMMMd(localeCode);

  return sortedKeys.map((day) {
    final diff = today.difference(day).inDays;
    String label;
    if (diff == 0) {
      label = l.activityDayToday;
    } else if (diff == 1) {
      label = l.activityDayYesterday;
    } else if (diff > 1 && diff <= 6) {
      label = l.activityDayDaysAgo(diff);
    } else {
      label = formatter.format(day);
    }
    return ActivityDayGroup(label: label, entries: groups[day]!);
  }).toList(growable: false);
}
