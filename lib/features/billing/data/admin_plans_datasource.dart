import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/plan.dart';

/// Acceso admin al catálogo. Reads van por SELECT directo (RLS permite a
/// admin ver TODOS los planes, no solo `is_active=true`). Writes que solo
/// tocan BD también van directos (RLS admin); las que requieren tocar
/// Stripe pasan por la Edge Function `admin-plans`.
class AdminPlansDataSource {
  const AdminPlansDataSource(this._client);

  final SupabaseClient _client;

  /// Todos los planes (incluyendo `is_active=false`). RLS lo permite a
  /// admin; usuarios normales ven solo los activos.
  Future<List<Plan>> listAllPlans() async {
    final data = await _client.from('plans').select().order('position');
    return (data as List)
        .map((row) => Plan.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Actualiza metadata del plan (no precios — eso es 1.F.2) y sincroniza
  /// con Stripe via Edge Function. Si Stripe no está configurado, los
  /// cambios de BD se aplican igual; la respuesta lleva
  /// `stripe_sync_warning` con el motivo.
  Future<({Plan plan, String? stripeSyncWarning})> updateMetadata({
    required String planId,
    String? name,
    String? description,
    Map<String, dynamic>? features,
    int? position,
    bool? isActive,
  }) async {
    final response = await _client.functions.invoke(
      'admin-plans',
      body: {
        'action': 'update_metadata',
        'plan_id': planId,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (features != null) 'features': features,
        if (position != null) 'position': position,
        if (isActive != null) 'is_active': isActive,
      },
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) {
      throw const AdminPlanException('empty_response');
    }
    if (payload['error'] != null) {
      throw AdminPlanException(payload['error'] as String);
    }
    final planMap = payload['plan'] as Map<String, dynamic>;
    return (
      plan: Plan.fromMap(planMap),
      stripeSyncWarning: payload['stripe_sync_warning'] as String?,
    );
  }

  /// Backfill puntual: recorre planes con price_id pero sin product_id y
  /// los resuelve vía Stripe. Idempotente, llamable a mano.
  Future<int> backfillStripeProductIds() async {
    final response = await _client.functions.invoke(
      'admin-plans',
      body: {'action': 'backfill_product_ids'},
    );
    final payload = response.data as Map<String, dynamic>?;
    return (payload?['updated'] as int?) ?? 0;
  }
}

class AdminPlanException implements Exception {
  const AdminPlanException(this.code);
  final String code;
  @override
  String toString() => 'AdminPlanException($code)';
}
