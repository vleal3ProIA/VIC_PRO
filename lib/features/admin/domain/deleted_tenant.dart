import 'package:meta/meta.dart';

/// Tenant soft-borrado tal y como lo devuelve la RPC
/// `public.list_deleted_tenants()`. Es un VO solo lectura, exclusivo de
/// la pantalla `/admin/trash`. NO reutilizamos `Tenant` del módulo
/// `features/tenants/` porque el invariante de aquel asume que el
/// tenant está vivo y se accede vía sesión del propio user.
@immutable
class DeletedTenant {
  const DeletedTenant({
    required this.id,
    required this.name,
    required this.slug,
    required this.ownerId,
    required this.deletedAt,
    required this.memberCount,
  });

  factory DeletedTenant.fromMap(Map<String, dynamic> m) {
    return DeletedTenant(
      id: m['id'] as String,
      name: m['name'] as String,
      slug: m['slug'] as String,
      ownerId: m['owner_id'] as String,
      deletedAt: DateTime.parse(m['deleted_at'] as String),
      memberCount: (m['member_count'] as num).toInt(),
    );
  }

  final String id;
  final String name;
  final String slug;
  final String ownerId;
  final DateTime deletedAt;
  final int memberCount;
}
