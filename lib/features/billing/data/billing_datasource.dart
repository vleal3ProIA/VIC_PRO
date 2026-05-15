import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entitlements.dart';
import '../domain/plan.dart';
import '../domain/tenant_subscription.dart';

class BillingDataSource {
  const BillingDataSource(this._client);

  final SupabaseClient _client;

  /// Catálogo de planes activos (RLS deja ver todos los `is_active=true`).
  Future<List<Plan>> listActivePlans() async {
    final data = await _client
        .from('plans')
        .select()
        .eq('is_active', true)
        .order('position');
    return (data as List)
        .map((row) => Plan.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Suscripción "viva" del tenant (trialing/active/past_due/incomplete).
  /// Devuelve `null` si no hay ninguna.
  Future<TenantSubscription?> currentSubscriptionFor(String tenantId) async {
    final data = await _client
        .from('tenant_subscriptions')
        .select()
        .eq('tenant_id', tenantId)
        .inFilter('status', const ['trialing', 'active', 'past_due', 'incomplete'])
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return TenantSubscription.fromMap(data);
  }

  /// Entitlements del plan activo del tenant. Devuelve [Entitlements.empty]
  /// si no hay nada o el caller no es miembro (RLS).
  Future<Entitlements> entitlementsFor(String tenantId) async {
    final raw = await _client.rpc<Object?>(
      'tenant_entitlements',
      params: {'p_tenant_id': tenantId},
    );
    if (raw is Map<String, dynamic>) return Entitlements(raw);
    if (raw is Map) return Entitlements(Map<String, dynamic>.from(raw));
    return const Entitlements.empty();
  }
}
