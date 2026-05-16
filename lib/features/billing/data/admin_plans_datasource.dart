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

  /// Preview del impacto de un cambio de precio: cuántas suscripciones
  /// activas tiene el plan actualmente. La UI lo usa para mostrar al
  /// admin "vas a afectar a N clientes" antes de aplicar.
  Future<({int activeSubscriptionsCount, int? currentMonthlyCents, int? currentYearlyCents, String? currency})>
      previewPriceChange({required String planId}) async {
    final response = await _client.functions.invoke(
      'admin-plans-prices',
      body: {'action': 'preview', 'plan_id': planId},
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) throw const AdminPlanException('empty_response');
    if (payload['error'] != null) {
      throw AdminPlanException(payload['error'] as String);
    }
    final cur = (payload['current'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (
      activeSubscriptionsCount:
          (payload['active_subscriptions_count'] as int?) ?? 0,
      currentMonthlyCents: cur['price_monthly_cents'] as int?,
      currentYearlyCents: cur['price_yearly_cents'] as int?,
      currency: cur['currency'] as String?,
    );
  }

  /// Aplica el cambio de precio. Crea Prices nuevos en Stripe, actualiza
  /// la BD, y (opcionalmente) migra las suscripciones existentes según
  /// la `migrationStrategy`:
  ///
  /// - `grandfather` → clientes existentes siguen con el viejo precio.
  /// - `nextPeriod`  → migran al inicio del próximo periodo, sin proration.
  /// - `immediate`   → migran ya con proration prorrateado.
  Future<({int migratedCount, List<({String subscriptionId, String detail})> errors})>
      applyPriceChange({
    required String planId,
    required PriceMigrationStrategy migrationStrategy,
    int? newMonthlyCents,
    int? newYearlyCents,
  }) async {
    final response = await _client.functions.invoke(
      'admin-plans-prices',
      body: {
        'action': 'apply',
        'plan_id': planId,
        if (newMonthlyCents != null) 'new_price_monthly_cents': newMonthlyCents,
        if (newYearlyCents != null) 'new_price_yearly_cents': newYearlyCents,
        'migration_strategy': migrationStrategy.apiValue,
      },
    );
    final payload = response.data as Map<String, dynamic>?;
    if (payload == null) throw const AdminPlanException('empty_response');
    if (payload['error'] != null) {
      throw AdminPlanException(payload['error'] as String);
    }
    final errs = ((payload['errors'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (m) => (
            subscriptionId: m['subscription_id'] as String,
            detail: m['detail'] as String,
          ),
        )
        .toList(growable: false);
    return (
      migratedCount: (payload['migrated_count'] as int?) ?? 0,
      errors: errs,
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

/// Estrategia de migración de suscripciones al cambiar el precio del plan.
enum PriceMigrationStrategy {
  /// No tocar las suscripciones existentes — siguen con el viejo precio.
  /// Solo NUEVOS contratos pagan el nuevo precio.
  grandfather,

  /// Migrar al final del periodo actual (sin proration). El cliente ya
  /// pagó este periodo y verá el nuevo precio en la próxima factura.
  nextPeriod,

  /// Migrar inmediatamente con proration: Stripe cobra o abona la
  /// diferencia prorrateada por los días restantes.
  immediate;

  String get apiValue {
    switch (this) {
      case PriceMigrationStrategy.grandfather:
        return 'grandfather';
      case PriceMigrationStrategy.nextPeriod:
        return 'next_period';
      case PriceMigrationStrategy.immediate:
        return 'immediate';
    }
  }
}
