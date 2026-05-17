import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/admin_users_datasource.dart';
import '../domain/admin_user.dart';

final adminUsersDataSourceProvider = Provider<AdminUsersDataSource>((ref) {
  return AdminUsersDataSource(ref.watch(supabaseClientProvider));
});

/// KPIs cards. Se invalida tras cualquier acción admin (block, change
/// plan, etc.) — los counts pueden haber cambiado.
final adminUsersKpisProvider = FutureProvider<AdminUsersKpis>((ref) async {
  final ds = ref.watch(adminUsersDataSourceProvider);
  return ds.kpis();
});

/// Filtros + paginación de la tabla. Inmutable, se reemplaza con copyWith.
@immutable
class AdminUsersQuery {
  const AdminUsersQuery({
    this.search = '',
    this.status = 'all',
    this.planSlug = 'all',
    this.offset = 0,
    this.limit = 50,
  });

  final String search;
  final String status; // 'all' | 'active' | 'blocked' | 'deactivated'
  final String planSlug; // 'all' | slug
  final int offset;
  final int limit;

  AdminUsersQuery copyWith({
    String? search,
    String? status,
    String? planSlug,
    int? offset,
    int? limit,
  }) {
    return AdminUsersQuery(
      search: search ?? this.search,
      status: status ?? this.status,
      planSlug: planSlug ?? this.planSlug,
      offset: offset ?? this.offset,
      limit: limit ?? this.limit,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdminUsersQuery &&
      other.search == search &&
      other.status == status &&
      other.planSlug == planSlug &&
      other.offset == offset &&
      other.limit == limit;

  @override
  int get hashCode =>
      Object.hash(search, status, planSlug, offset, limit);
}

/// Estado mutable de filtros — la UI lo cambia y eso re-dispara la
/// query. Default: sin search, todos los estados, offset 0.
final adminUsersQueryProvider =
    StateProvider<AdminUsersQuery>((_) => const AdminUsersQuery());

/// Página de la tabla. `.family` por la query para que cambiar filtros
/// no invalide la página anterior (mejor UX al volver atrás).
final adminUsersPageProvider =
    FutureProvider.family<AdminUsersListResult, AdminUsersQuery>((ref, query) async {
  final ds = ref.watch(adminUsersDataSourceProvider);
  return ds.list(
    search: query.search,
    status: query.status,
    planSlug: query.planSlug,
    offset: query.offset,
    limit: query.limit,
  );
});

/// Detalle de un user, `.family` por id.
final adminUserDetailProvider =
    FutureProvider.family<AdminUserDetail, String>((ref, userId) async {
  final ds = ref.watch(adminUsersDataSourceProvider);
  return ds.detail(userId);
});
