import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';

import '../../application/admin_plans_providers.dart';
import '../../domain/plan.dart';
import '../widgets/admin_plan_edit_dialog.dart';
import '../widgets/admin_plan_price_change_dialog.dart';

/// `/admin/plans` — gestión del catálogo (solo admin global).
///
/// Permite:
///   - Ver todos los planes (incluidos `is_active=false`).
///   - Editar nombre, descripción, features (form estructurado), position
///     y toggle activo/inactivo. Cambios sincronizados con Stripe vía
///     Edge Function `admin-plans`.
///   - **Precios**: read-only en esta PR (1.F.1). El flujo de cambio de
///     precio con migración de Stripe Price es 1.F.2.
class AdminPlansPage extends ConsumerWidget {
  const AdminPlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final plansAsync = ref.watch(allPlansAdminProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.admin),
        ),
        title: Text(l.adminPlansTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allPlansAdminProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: plansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                l.adminPlansLoadError,
                style: TextStyle(color: context.colors.error),
              ),
            ),
            data: (plans) {
              if (plans.isEmpty) {
                return Center(child: Text(l.adminPlansEmpty));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: plans.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _PlanRow(plan: plans[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PlanRow extends ConsumerWidget {
  const _PlanRow({required this.plan});
  final Plan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final priceMonthly = plan.formatPrice(yearly: false);
    final priceYearly = plan.formatPrice(yearly: true);
    final inactive = !plan.isActive;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plan.name,
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              decoration: inactive
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: inactive
                                  ? context.colors.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              plan.slug,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (inactive) ...[
                            const SizedBox(width: 8),
                            Chip(
                              label: Text(l.adminPlansInactive),
                              backgroundColor: context.colors.errorContainer,
                              side: BorderSide.none,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ],
                      ),
                      if (plan.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          plan.description!,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        children: [
                          _MetaChip(
                            icon: Icons.calendar_month,
                            label: '$priceMonthly/${l.plansPerMonth}',
                          ),
                          _MetaChip(
                            icon: Icons.event_note,
                            label: '$priceYearly/${l.plansPerYear}',
                          ),
                          _MetaChip(
                            icon: Icons.format_list_numbered,
                            label: 'pos=${plan.position}',
                          ),
                          _MetaChip(
                            icon: Icons.code,
                            label: '${plan.features.length} features',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l.adminPlansChangePriceTooltip,
                  icon: const Icon(Icons.payments_outlined),
                  onPressed: plan.isFree || plan.isCustomPriced
                      ? null
                      : () => _onChangePrice(context, ref),
                ),
                IconButton(
                  tooltip: l.adminPlansEditTooltip,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _onEdit(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onEdit(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AdminPlanEditDialog(plan: plan),
    );
    if ((result ?? false) && context.mounted) {
      invalidatePlanCaches(ref);
    }
  }

  Future<void> _onChangePrice(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AdminPlanPriceChangeDialog(plan: plan),
    );
    if ((result ?? false) && context.mounted) {
      invalidatePlanCaches(ref);
    }
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      );
}
