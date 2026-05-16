import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/billing_providers.dart';
import '../../data/billing_datasource.dart';
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
    final currentSub = ref.watch(currentSubscriptionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.accountSettings),
        ),
        title: Text(l.plansTitle),
        actions: [
          if (currentPlan != null && !currentPlan.isFree)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.credit_card_outlined, size: 18),
                label: Text(l.plansManageBilling),
                onPressed: () => _onManageBilling(context),
              ),
            ),
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
                  // Banner solo cuando hay una sub con cancelación
                  // programada — todavía activa pero termina pronto.
                  final showCancelBanner = currentSub != null &&
                      currentSub.cancelAtPeriodEnd &&
                      currentSub.currentPeriodEnd != null;

                  // 4 cols en desktop, 2 en tablet, 1 en mobile.
                  final cols = c.maxWidth >= 1100
                      ? 4
                      : c.maxWidth >= 700
                          ? 2
                          : 1;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showCancelBanner)
                        _CancelPendingBanner(
                          endsAt: currentSub.currentPeriodEnd!,
                          onReactivate: () => _onManageBilling(context),
                        ),
                      if (showCancelBanner) const SizedBox(height: 16),
                      Wrap(
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
                                // Un plan es "downgrade" si su `position`
                                // está por debajo del plan actual. Por
                                // convención de seed: free=10, pro=20,
                                // business=30, enterprise=40.
                                isDowngrade: currentPlan != null &&
                                    p.position < currentPlan.position,
                              ),
                            ),
                        ],
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

  /// Lanza el Customer Portal de Stripe en la pestaña actual.
  Future<void> _onManageBilling(BuildContext context) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) return;
    try {
      final url = await launchCustomerPortal(
        ref,
        tenantId: tenantId,
        returnUrl: Uri.base.toString(),
      );
      if (url == null || !context.mounted) return;
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
    } on BillingException catch (e) {
      if (!context.mounted) return;
      context.showSnack(
        e.code == 'stripe_not_configured'
            ? context.l10n.plansStripeNotConfigured
            : context.l10n.plansCheckoutFailed,
        isError: true,
      );
    } catch (_) {
      if (!context.mounted) return;
      context.showSnack(context.l10n.plansCheckoutFailed, isError: true);
    }
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.plan,
    required this.yearly,
    required this.isCurrent,
    required this.isDowngrade,
  });
  final Plan plan;
  final bool yearly;
  final bool isCurrent;
  /// `true` cuando este plan está por debajo del plan actual del tenant
  /// (menor `position`). Mostrar "Upgrade" sería incorrecto: el flujo de
  /// bajar de plan va por Customer Portal.
  final bool isDowngrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      : isDowngrade
                          // Plan por debajo del actual: para bajar el
                          // usuario tiene que ir al Customer Portal
                          // (cancelar/cambiar de plan). NO se "upgradea"
                          // a un plan inferior por checkout.
                          ? OutlinedButton(
                              onPressed: null,
                              child: Text(l.plansDowngradeViaPortal),
                            )
                          : _UpgradeButton(plan: plan, yearly: yearly),
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

/// Banner amarillo arriba del catálogo cuando la suscripción está
/// programada para cancelarse al final del periodo. Informa al usuario y
/// le ofrece reactivar (=> Customer Portal).
class _CancelPendingBanner extends StatelessWidget {
  const _CancelPendingBanner({
    required this.endsAt,
    required this.onReactivate,
  });

  final DateTime endsAt;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final formatted = DateFormat.yMMMMd(localeCode).format(endsAt.toLocal());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: context.colors.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.plansCancelPendingMessage(formatted),
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colors.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: onReactivate,
            child: Text(l.plansReactivate),
          ),
        ],
      ),
    );
  }
}

/// Botón "Upgrade" que invoca la Edge Function `stripe-checkout` y
/// redirige al usuario a la URL de Stripe Checkout (en la misma pestaña).
class _UpgradeButton extends ConsumerStatefulWidget {
  const _UpgradeButton({required this.plan, required this.yearly});
  final Plan plan;
  final bool yearly;
  @override
  ConsumerState<_UpgradeButton> createState() => _UpgradeButtonState();
}

class _UpgradeButtonState extends ConsumerState<_UpgradeButton> {
  bool _busy = false;

  Future<void> _onPressed() async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) return;
    setState(() => _busy = true);
    try {
      final base = Uri.base;
      final success = Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort && base.port != 80 && base.port != 443
            ? base.port
            : null,
        path: RoutePaths.billingSuccess,
        queryParameters: const {'session_id': '{CHECKOUT_SESSION_ID}'},
      ).toString();
      final cancel = Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort && base.port != 80 && base.port != 443
            ? base.port
            : null,
        path: RoutePaths.plans,
      ).toString();

      final url = await launchCheckout(
        ref,
        tenantId: tenantId,
        planSlug: widget.plan.slug,
        billingPeriod: widget.yearly ? 'yearly' : 'monthly',
        successUrl: success,
        cancelUrl: cancel,
      );
      if (url == null) return;
      // Web: full-page redirect en la misma pestaña.
      // url_launcher con webOnlyWindowName: '_self' lo logra.
      await launchUrl(
        Uri.parse(url),
        webOnlyWindowName: '_self',
      );
    } on BillingException catch (e) {
      if (!mounted) return;
      context.showSnack(_mapError(e.code), isError: true);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(context.l10n.plansCheckoutFailed, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mapError(String code) {
    final l = context.l10n;
    return switch (code) {
      'stripe_not_configured' => l.plansStripeNotConfigured,
      'rate_limited' => l.plansRateLimited,
      'not_admin' || 'not_member' => l.plansNotAdmin,
      _ => l.plansCheckoutFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _busy ? null : _onPressed,
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Text(context.l10n.plansUpgrade),
    );
  }
}
