import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/admin_user.dart';

/// Acceso a las RPCs admin_* + Edge Function admin-users. Admin-only;
/// las RPCs verifican `is_admin()` internamente y devuelven error si no.
class AdminUsersDataSource {
  const AdminUsersDataSource(this._client);

  final SupabaseClient _client;

  /// KPIs cards (counts por estado, distribución por plan, signups).
  Future<AdminUsersKpis> kpis() async {
    final data = await _client.rpc<dynamic>('admin_users_kpis');
    return AdminUsersKpis.fromMap(
      (data as Map).cast<String, dynamic>(),
    );
  }

  /// Lista paginada de users. El total viene replicado en cada row
  /// (columna `total_count`) — lo leemos del primer row o devolvemos 0.
  Future<AdminUsersListResult> list({
    String? search,
    String status = 'all', // 'all' | 'active' | 'blocked' | 'deactivated'
    String planSlug = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _client.rpc<dynamic>(
      'admin_list_users',
      params: {
        'p_search': (search?.trim().isNotEmpty ?? false) ? search!.trim() : null,
        'p_status': status,
        'p_plan_slug': planSlug,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    final list = (data as List).cast<Map<String, dynamic>>();
    final rows = list.map(AdminUserSummary.fromMap).toList(growable: false);
    final total = list.isEmpty
        ? 0
        : (list.first['total_count'] as num?)?.toInt() ?? 0;
    return AdminUsersListResult(rows: rows, totalCount: total);
  }

  /// Detalle completo. Lanza si no existe.
  Future<AdminUserDetail> detail(String userId) async {
    final data = await _client.rpc<dynamic>(
      'admin_get_user_detail',
      params: {'p_user_id': userId},
    );
    return AdminUserDetail.fromMap(
      (data as Map).cast<String, dynamic>(),
    );
  }

  /// Cambia el plan del user a uno FREE. Para planes de pago, debe
  /// hacerse desde Stripe Dashboard. Lanza si el plan tiene precio.
  Future<void> changePlanFree({
    required String userId,
    required String planId,
  }) async {
    await _client.rpc<void>(
      'admin_change_user_plan_free',
      params: {'p_user_id': userId, 'p_plan_id': planId},
    );
  }

  // ─────────────────────── Edge Function actions ───────────────────────

  /// Bloquea al user hasta la fecha indicada. La UI usa un date-time
  /// picker; el ISO se pasa tal cual a Supabase Auth.
  Future<AdminActionResult> block({
    required String userId,
    required DateTime until,
  }) async {
    return _invoke({
      'action': 'block',
      'user_id': userId,
      'until_iso': until.toUtc().toIso8601String(),
    });
  }

  Future<AdminActionResult> unblock(String userId) async {
    return _invoke({'action': 'unblock', 'user_id': userId});
  }

  Future<AdminActionResult> deactivate(String userId) async {
    return _invoke({'action': 'deactivate', 'user_id': userId});
  }

  Future<AdminActionResult> reactivate(String userId) async {
    return _invoke({'action': 'reactivate', 'user_id': userId});
  }

  /// Envía email individual al user con asunto + body HTML.
  Future<AdminActionResult> sendEmail({
    required String userId,
    required String subject,
    required String bodyHtml,
  }) async {
    return _invoke({
      'action': 'send_email',
      'user_id': userId,
      'subject': subject,
      'body_html': bodyHtml,
    });
  }

  Future<AdminActionResult> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('admin-users', body: body);
      final data = res.data;
      if (data is! Map) {
        return const AdminActionResult(ok: false, error: 'empty_response');
      }
      final payload = data.cast<String, dynamic>();
      return AdminActionResult(
        ok: payload['ok'] == true,
        error: payload['error'] as String?,
        detail: payload['detail'] as String?,
      );
    } on FunctionException catch (e) {
      return AdminActionResult(ok: false, error: 'http_${e.status}');
    } catch (_) {
      return const AdminActionResult(ok: false, error: 'unknown');
    }
  }
}

class AdminActionResult {
  const AdminActionResult({required this.ok, this.error, this.detail});
  final bool ok;
  final String? error;
  final String? detail;
}
