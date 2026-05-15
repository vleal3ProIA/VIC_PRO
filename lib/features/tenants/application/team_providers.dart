import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/observability/analytics_service.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/utils/log_context.dart';

import '../data/tenant_invitations_datasource.dart';
import '../domain/tenant_invitation.dart';
import '../domain/tenant_member.dart';
import '../domain/tenant_member_profile.dart';
import 'tenant_providers.dart';

/// Datasource de invitaciones expuesto como provider.
final tenantInvitationsDataSourceProvider =
    Provider<TenantInvitationsDataSource>((ref) {
  return TenantInvitationsDataSource(ref.watch(supabaseClientProvider));
});

/// Miembros del tenant actualmente activo, enriquecidos con perfil + email.
/// Se recalcula al cambiar de tenant. Si no hay tenant activo → vacío.
final currentTenantMembersProvider =
    FutureProvider<List<TenantMemberProfile>>((ref) async {
  final tenant = ref.watch(currentTenantProvider).valueOrNull;
  if (tenant == null) return const [];
  final ds = ref.watch(tenantDataSourceProvider);
  return ds.listMembersWithProfile(tenant.id);
});

/// Versión "raw" sin enriquecer — solo IDs + roles. Más rápida, útil
/// internamente o para tests.
final currentTenantMembersRawProvider =
    FutureProvider<List<TenantMember>>((ref) async {
  final tenant = ref.watch(currentTenantProvider).valueOrNull;
  if (tenant == null) return const [];
  final ds = ref.watch(tenantDataSourceProvider);
  return ds.listMembers(tenant.id);
});

/// Invitaciones del tenant actualmente activo. RLS solo deja verlas si soy
/// admin del tenant; si no, devuelve lista vacía (no es error).
final currentTenantInvitationsProvider =
    FutureProvider<List<TenantInvitation>>((ref) async {
  final tenant = ref.watch(currentTenantProvider).valueOrNull;
  if (tenant == null) return const [];
  final ds = ref.watch(tenantInvitationsDataSourceProvider);
  try {
    return await ds.listForTenant(tenant.id);
  } catch (_) {
    // Si no soy admin, la RLS no devuelve filas (no es error). Si hay otro
    // problema (red, etc.), devolvemos vacío en lugar de propagar — la UI
    // muestra la lista de miembros sin la sección de invitaciones.
    return const [];
  }
});

// ─── Acciones (helpers para llamar desde widgets) ─────────────────────────
//
// Las acciones aceptan `WidgetRef` porque siempre se invocan desde la UI.
// Si en el futuro las necesitas desde un notifier (con `Ref`), sobrecarga
// o extrae el cuerpo a una función privada que tome ambos.

/// Crea una invitación, dispara analytics y refresca la lista. Devuelve el
/// `CreatedInvitation` para que la UI muestre el link al admin (solo se ve
/// UNA vez).
Future<CreatedInvitation> createInvitation(
  WidgetRef ref, {
  required String tenantId,
  required String email,
  required TenantRole role,
}) async {
  return LogContext.run<CreatedInvitation>(
    tags: {'flow': 'invite_create', 'tenant_id': tenantId},
    () async {
      final ds = ref.read(tenantInvitationsDataSourceProvider);
      final analytics = ref.read(analyticsServiceProvider);
      final result = await ds.create(
        tenantId: tenantId,
        email: email,
        role: role,
      );
      analytics.trackSync(
        'tenant_invitation_created',
        properties: {'role': role.toDbString()},
      );
      ref.invalidate(currentTenantInvitationsProvider);
      return result;
    },
  );
}

/// Acepta una invitación; refresca tenants y deja al usuario en el nuevo
/// tenant. Devuelve el `tenant_id` resultante para que la UI navegue.
Future<String> acceptInvitation(WidgetRef ref, String token) async {
  return LogContext.run<String>(
    tags: {'flow': 'invite_accept'},
    () async {
      final ds = ref.read(tenantInvitationsDataSourceProvider);
      final analytics = ref.read(analyticsServiceProvider);
      final result = await ds.accept(token);

      analytics.trackSync(
        'tenant_invitation_accepted',
        properties: {'role': result.role.toDbString()},
      );

      // Refrescamos la lista de tenants del usuario y le hacemos current el
      // tenant al que acaba de unirse.
      ref.invalidate(myTenantsProvider);
      final tenants = await ref.read(myTenantsProvider.future);
      final joined = tenants.where((t) => t.id == result.tenantId).firstOrNull;
      if (joined != null) {
        await ref.read(currentTenantProvider.notifier).setCurrent(joined.id);
      }
      return result.tenantId;
    },
  );
}

/// Revoca una invitación pendiente. Refresca la lista.
Future<void> revokeInvitation(WidgetRef ref, String invitationId) async {
  await ref.read(tenantInvitationsDataSourceProvider).revoke(invitationId);
  ref.read(analyticsServiceProvider).trackSync('tenant_invitation_revoked');
  ref.invalidate(currentTenantInvitationsProvider);
}
