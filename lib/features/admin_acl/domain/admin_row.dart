// ============================================================================
// Admin ACL · Domain (PR-Super-A2)
// ----------------------------------------------------------------------------
// Modelo inmutable que matchea las filas devueltas por la RPC SQL
// `super_admin_list_admins()` (migracion 0044).
// ============================================================================

import 'package:meta/meta.dart';

@immutable
class AdminRow {
  const AdminRow({
    required this.userId,
    required this.email,
    required this.isSuperAdmin,
    required this.capabilities,
    required this.createdAt,
    this.displayName,
  });

  factory AdminRow.fromMap(Map<String, dynamic> m) {
    final rawCaps = m['capabilities'];
    final caps = (rawCaps is List)
        ? rawCaps.whereType<String>().toSet()
        : <String>{};
    return AdminRow(
      userId: m['user_id'] as String,
      email: m['email'] as String? ?? '',
      displayName: m['display_name'] as String?,
      isSuperAdmin: m['is_super_admin'] as bool? ?? false,
      capabilities: caps,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }

  final String userId;
  final String email;
  final String? displayName;
  final bool isSuperAdmin;
  final Set<String> capabilities;
  final DateTime createdAt;

  /// Nombre legible para la UI: display_name si lo tiene, sino email.
  String get bestDisplayName {
    final d = displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    return email;
  }
}
