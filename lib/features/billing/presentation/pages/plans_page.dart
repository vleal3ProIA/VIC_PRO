import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';

import '../../application/billing_providers.dart';
import '../../domain/plan.dart';

/// Pantalla `/billing/plans` — catálogo de planes + indicador del actual.
/// El botón "Upgrade" muestra un placeholder por ahora; la integración con
/// Stripe llegará en la PR siguiente (1.E).
class PlansPage extends ConsumerStatefulWidget {
  const PlansPage({super.key});

  @override
  ConsumerState<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends ConsumerState<PlansPage> {
  bool _yearly = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plansAsync = ref.watch(plansProvider);
    final currentPlan = ref.watch(currentPlanProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.accountSettings),
        ),
        title: Text(l.plansTitle),
        actions: [
          // Toggle Monthly / Yearly.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l.plansBillingMonthly)),
                ButtonSegment(value: true, label: Text(l.plansBillingYearly)),
              ],
              selected: {_yearly},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _yearly = s.first),
            ),
          ),
        ],
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            l.plansLoadError,
            style: TextStyle(color: context.colors.error),
          ),
        ),
        data: (plans) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (ctx, c) {
                  // 4 cols en desktop, 2 en tablet, 1 en mobile.
                  final cols = c.maxWidth >= 1100
                      ? 4
                      : c.maxWidth >= 700
                          ? 2
                          : 1;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final p in plans)
                        SizedBox(
                          width: (c.maxWidth - (cols - 1) * 16) / cols,
                          child: _PlanCard(
                            plan: p,
                            yearly: _yearly,
                            isCurrent: currentPlan?.id == p.id,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.yearly,
    required this.isCurrent,
  });
  final Plan plan;
  final bool yearly;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final priceText = plan.formatPrice(yearly: yearly);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isCurrent ? context.colors.primary : context.colors.outlineVariant,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  plan.name,
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (isCurrent)
                  Chip(
                    label: Text(l.plansCurrentBadge),
                    backgroundColor: context.colors.primaryContainer,
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
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
            const SizedBox(height: 20),
            // Precio.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  priceText,
                  style: context.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!plan.isCustomPriced && !plan.isFree) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      yearly ? '/${l.plansPerYear}' : '/${l.plansPerMonth}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            // Features list (humanizada).
            ..._humanizeFeatures(context, plan.features).map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(line, style: context.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: isCurrent
                  ? OutlinedButton(
                      onPressed: null,
                      child: Text(l.plansCurrentPlan),
                    )
                  : plan.isCustomPriced
                      ? OutlinedButton(
                          onPressed: () {
                            context.showSnack(l.plansContactSales);
                          },
                          child: Text(l.plansContactSales),
                        )
                      : FilledButton(
                          onPressed: () {
                            // Stripe llega en 1.E — placeholder por ahora.
                            context.showSnack(l.plansUpgradeComingSoon);
                          },
                          child: Text(l.plansUpgrade),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Convierte el mapa `features` a líneas legibles. Renderizamos las
  /// claves conocidas con copy localizado; las desconocidas las saltamos
  /// para no enseñar "ai_credits: 1000" sin traducir.
  List<String> _humanizeFeatures(
    BuildContext context,
    Map<String, dynamic> features,
  ) {
    final l = context.l10n;
    final out = <String>[];

    int? intVal(String key) {
      final v = features[key];
      return v is int ? v : (v is num ? v.toInt() : null);
    }

    bool? boolVal(String key) {
      final v = features[key];
      return v is bool ? v : null;
    }

    final maxMembers = intVal('max_members');
    if (maxMembers != null) {
      out.add(maxMembers < 0
          ? l.planFeatureUnlimitedMembers
          : l.planFeatureMembers(maxMembers.toString()),);
    }

    final maxStorage = intVal('max_storage_gb');
    if (maxStorage != null) {
      out.add(maxStorage < 0
          ? l.planFeatureUnlimitedStorage
          : l.planFeatureStorageGb(maxStorage.toString()),);
    }

    final aiCredits = intVal('ai_credits');
    if (aiCredits != null && aiCredits > 0) {
      out.add(aiCredits < 0
          ? l.planFeatureUnlimitedAiCredits
          : l.planFeatureAiCredits(aiCredits.toString()),);
    }

    final support = features['support'] as String?;
    if (support != null) {
      out.add(
        switch (support) {
          'community' => l.planFeatureSupportCommunity,
          'email' => l.planFeatureSupportEmail,
          'priority' => l.planFeatureSupportPriority,
          'dedicated' => l.planFeatureSupportDedicated,
          _ => support,
        },
      );
    }

    if (boolVal('custom_domain') ?? false) out.add(l.planFeatureCustomDomain);
    if (boolVal('sso') ?? false) out.add(l.planFeatureSso);
    if (boolVal('white_label') ?? false) out.add(l.planFeatureWhiteLabel);

    return out;
  }
}
