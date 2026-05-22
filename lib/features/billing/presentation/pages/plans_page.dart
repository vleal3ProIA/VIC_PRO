import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/billing_info_providers.dart';
import '../../application/billing_providers.dart';
import '../../application/promotion_code_providers.dart';
import '../../data/billing_datasource.dart';
import '../../domain/plan.dart';
import '../../domain/promotion_code.dart';
import '../widgets/promotion_code_field.dart';

/// Pantalla `/billing/plans` — catálogo de planes + indicador del actual.
/// El botón "Upgrade" muestra un placeholder por ahora; la integración con
/// Stripe llegará en la PR siguiente (1.E).
class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.accountSettings),
        ),
        title: Text(l.plansTitle),
      ),
      body: const PlansView(),
    );
  }
}

/// Cuerpo del catálogo de planes (sin Scaffold). Reutilizable como página
/// completa o embebido en el master-detail de Ajustes → Facturación.
///
/// Toda la lógica de Stripe (checkout/cambio/cancelación/portal) queda
/// intacta: solo se reubica el envoltorio. Las acciones que vivían en el
/// AppBar (gestionar facturación + selector mensual/anual) pasan a una fila
/// dentro del propio cuerpo.
class PlansView extends ConsumerStatefulWidget {
  const PlansView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Ajustes).
  final bool embedded;

  @override
  ConsumerState<PlansView> createState() => _PlansViewState();
}

class _PlansViewState extends ConsumerState<PlansView> {
  bool _yearly = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plansAsync = ref.watch(plansProvider);
    final currentPlan = ref.watch(currentPlanProvider).valueOrNull;
    final currentSub = ref.watch(currentSubscriptionProvider).valueOrNull;

    // Fila de acciones (antes en el AppBar): gestionar facturación (solo si
    // hay un Stripe customer real) + selector mensual/anual.
    final actions = Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Solo mostramos "Manage billing" si HAY un Stripe customer real
          // que gestionar. Esto excluye:
          //   - usuarios en plan Free (no han pasado por checkout nunca)
          //   - clientes Enterprise gestionados manualmente (sin sub Stripe)
          //   - cualquier escenario sin stripe_customer_id
          if (currentSub?.stripeCustomerId != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.credit_card_outlined, size: 18),
                label: Text(l.plansManageBilling),
                onPressed: () => _onManageBilling(context),
              ),
            ),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(l.plansBillingMonthly)),
              ButtonSegment(value: true, label: Text(l.plansBillingYearly)),
            ],
            selected: {_yearly},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _yearly = s.first),
          ),
        ],
      ),
    );

    final body = plansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(
          l.plansLoadError,
          style: TextStyle(color: context.colors.error),
        ),
      ),
      data: (plans) {
        final grid = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: double.infinity),
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
                        subscriptionId: currentSub.stripeSubscriptionId ?? '',
                      ),
                    if (showCancelBanner) const SizedBox(height: 16),
                    const PromotionCodeField(),
                    const SizedBox(height: 16),
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
                              // Si hay sub Stripe viva, los botones usan
                              // change_plan; si no (Free), embedded checkout.
                              stripeSubscriptionId:
                                  currentSub?.stripeSubscriptionId,
                              cancelPending:
                                  currentSub?.cancelAtPeriodEnd ?? false,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
        // Embebido: sin scroll propio (lo provee el master-detail). Pantalla
        // completa: SingleChildScrollView con su padding.
        return widget.embedded
            ? Padding(padding: const EdgeInsets.all(24), child: grid)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: grid,
              );
      },
    );

    return Column(
      mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
      children: [
        actions,
        if (widget.embedded) body else Expanded(child: body),
      ],
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
    required this.stripeSubscriptionId,
    required this.cancelPending,
  });
  final Plan plan;
  final bool yearly;
  final bool isCurrent;
  final bool isDowngrade;

  /// ID de la suscripción Stripe viva del tenant. Si no es null, los
  /// cambios de plan van por `change_plan` API (sin checkout). Si es
  /// null, el upgrade va por embedded checkout (primera compra).
  final String? stripeSubscriptionId;

  /// True si la sub viva está marcada para cancelarse al final del periodo.
  final bool cancelPending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final priceText = plan.formatPrice(yearly: yearly);
    final applied = ref.watch(appliedPromotionCodeProvider);
    // Solo aplicamos visualmente el descuento si el cupón aplica a este
    // plan (o aplica a todos). El backend revalida en el checkout.
    final discountApplies = applied != null &&
        _appliesToPlan(applied, plan.slug) &&
        !plan.isFree &&
        !plan.isCustomPriced;
    final basePriceCents =
        yearly ? plan.priceYearlyCents : plan.priceMonthlyCents;
    final discountedPriceText =
        discountApplies && basePriceCents != null && basePriceCents > 0
            ? _formatCents(
                applied.applyToPriceCents(basePriceCents),
                plan.currency,
              )
            : null;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isCurrent
              ? context.colors.primary
              : context.colors.outlineVariant,
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
            // Precio (con tachado si hay descuento aplicado a este plan).
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (discountedPriceText != null) ...[
                  Text(
                    discountedPriceText,
                    style: context.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: context.colors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      priceText,
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ] else
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
            _PlanCardAction(
              plan: plan,
              yearly: yearly,
              isCurrent: isCurrent,
              isDowngrade: isDowngrade,
              stripeSubscriptionId: stripeSubscriptionId,
              cancelPending: cancelPending,
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
      out.add(
        maxMembers < 0
            ? l.planFeatureUnlimitedMembers
            : l.planFeatureMembers(maxMembers.toString()),
      );
    }

    final maxStorage = intVal('max_storage_gb');
    if (maxStorage != null) {
      out.add(
        maxStorage < 0
            ? l.planFeatureUnlimitedStorage
            : l.planFeatureStorageGb(maxStorage.toString()),
      );
    }

    final aiCredits = intVal('ai_credits');
    if (aiCredits != null && aiCredits > 0) {
      out.add(
        aiCredits < 0
            ? l.planFeatureUnlimitedAiCredits
            : l.planFeatureAiCredits(aiCredits.toString()),
      );
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

  bool _appliesToPlan(AppliedPromotionCode applied, String slug) {
    final list = applied.appliesToPlanSlugs;
    if (list == null || list.isEmpty) return true;
    return list.contains(slug);
  }

  String _formatCents(int cents, String? currency) {
    final value = cents / 100.0;
    final sym = switch (currency) {
      'USD' => r'$',
      'GBP' => '£',
      _ => '€',
    };
    return '${value.toStringAsFixed(2)} $sym';
  }
}

/// Banner amarillo arriba del catálogo cuando la suscripción está
/// programada para cancelarse al final del periodo. Informa al usuario y
/// le ofrece reactivar (=> Customer Portal).
/// Banner amarillo cuando la sub está pendiente de cancelarse al fin de
/// periodo. El botón "Reactivar" llama a la Edge Function
/// `stripe-subscription-update` con `action: reactivate` — sin abrir
/// Customer Portal.
class _CancelPendingBanner extends ConsumerStatefulWidget {
  const _CancelPendingBanner({
    required this.endsAt,
    required this.subscriptionId,
  });

  final DateTime endsAt;
  final String subscriptionId;

  @override
  ConsumerState<_CancelPendingBanner> createState() =>
      _CancelPendingBannerState();
}

class _CancelPendingBannerState extends ConsumerState<_CancelPendingBanner> {
  bool _busy = false;

  Future<void> _onReactivate() async {
    if (widget.subscriptionId.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(billingDataSourceProvider)
          .reactivateSubscription(widget.subscriptionId);
      // Refresca el estado de la sub — el banner desaparece solo cuando
      // `cancel_at_period_end` pase a false (Stripe envía webhook).
      ref
        ..invalidate(currentSubscriptionProvider)
        ..invalidate(currentPlanProvider)
        ..invalidate(currentEntitlementsProvider);
      if (!mounted) return;
      context.showSnack(context.l10n.plansReactivated);
    } on BillingException catch (e) {
      if (!mounted) return;
      context.showSnack(
        e.code == 'rate_limited'
            ? context.l10n.plansRateLimited
            : context.l10n.plansCheckoutFailed,
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnack(context.l10n.plansCheckoutFailed, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final formatted =
        DateFormat.yMMMMd(localeCode).format(widget.endsAt.toLocal());
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
            onPressed: _busy ? null : _onReactivate,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Text(l.plansReactivate),
          ),
        ],
      ),
    );
  }
}

/// Decide qué botón mostrar bajo cada card en función del plan iterado vs
/// el plan actual del tenant. Centraliza la lógica que antes vivía
/// inline en `_PlanCard`.
class _PlanCardAction extends ConsumerStatefulWidget {
  const _PlanCardAction({
    required this.plan,
    required this.yearly,
    required this.isCurrent,
    required this.isDowngrade,
    required this.stripeSubscriptionId,
    required this.cancelPending,
  });

  final Plan plan;
  final bool yearly;
  final bool isCurrent;
  final bool isDowngrade;
  final String? stripeSubscriptionId;
  final bool cancelPending;

  @override
  ConsumerState<_PlanCardAction> createState() => _PlanCardActionState();
}

class _PlanCardActionState extends ConsumerState<_PlanCardAction> {
  bool _busy = false;

  bool get _hasPaidSub =>
      widget.stripeSubscriptionId != null &&
      widget.stripeSubscriptionId!.isNotEmpty;

  /// Confirma con el user y ejecuta `change_plan` API.
  Future<void> _onChangePlan() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.plansChangeConfirmTitle(widget.plan.name)),
        content: Text(l.plansChangeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.plansChangeConfirmAction),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(billingDataSourceProvider).changeSubscriptionPlan(
            subscriptionId: widget.stripeSubscriptionId!,
            newPlanSlug: widget.plan.slug,
            newBillingPeriod: widget.yearly ? 'yearly' : 'monthly',
          );
      ref
        ..invalidate(currentSubscriptionProvider)
        ..invalidate(currentPlanProvider)
        ..invalidate(currentEntitlementsProvider);
      if (!mounted) return;
      context.showSnack(l.plansChanged(widget.plan.name));
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

  /// Confirma y cancela la sub al fin de periodo.
  Future<void> _onCancel() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.plansCancelConfirmTitle),
        content: Text(l.plansCancelConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.errorContainer,
              foregroundColor: context.colors.onErrorContainer,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.plansCancelConfirmAction),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(billingDataSourceProvider)
          .cancelSubscription(widget.stripeSubscriptionId!);
      ref
        ..invalidate(currentSubscriptionProvider)
        ..invalidate(currentPlanProvider)
        ..invalidate(currentEntitlementsProvider);
      if (!mounted) return;
      context.showSnack(l.plansCancelScheduled);
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
    final l = context.l10n;

    // Plan actual:
    if (widget.isCurrent) {
      // Hay sub paga y NO está cancelándose → botón Cancel disponible.
      if (_hasPaidSub && !widget.cancelPending) {
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: null,
                child: Text(l.plansCurrentPlan),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _onCancel,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(l.plansCancelSubscription),
            ),
          ],
        );
      }
      // Free o sub cancel-pending: solo "Current plan", el banner ya
      // gestiona el reactivate.
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: null,
          child: Text(l.plansCurrentPlan),
        ),
      );
    }

    // Plan con precio custom (Enterprise): Contact sales.
    if (widget.plan.isCustomPriced) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => context.showSnack(l.plansContactSales),
          child: Text(l.plansContactSales),
        ),
      );
    }

    // Free card mientras el user tiene sub paga: "Switch to Free" = cancel.
    if (widget.plan.isFree && _hasPaidSub) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : _onCancel,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Text(l.plansSwitchToFree),
        ),
      );
    }

    // Plan inferior (downgrade) y sub paga → change_plan API.
    if (widget.isDowngrade && _hasPaidSub) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : _onChangePlan,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Text(l.plansSwitchTo(widget.plan.name)),
        ),
      );
    }

    // Plan superior (upgrade):
    //  - Con sub Stripe → change_plan API (sin checkout).
    //  - Sin sub Stripe (Free user) → embedded checkout.
    if (_hasPaidSub) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : _onChangePlan,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Text(l.plansSwitchTo(widget.plan.name)),
        ),
      );
    }

    // Sin sub Stripe → embedded checkout.
    return SizedBox(
      width: double.infinity,
      child: _UpgradeButton(plan: widget.plan, yearly: widget.yearly),
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
      // Gate: el usuario debe tener su billing info completa ANTES de pagar.
      // Usamos `.future` para AWAITar a que el provider termine de cargar —
      // si solo leyéramos sync con `valueOrNull`, durante un instante el
      // provider está `loading` y valueOrNull devuelve null → gate triggea
      // por error → reenvío al form aunque YA tenga los datos.
      final info = await ref.read(myBillingInfoProvider.future);
      if (!info.isCompleteForBilling) {
        final ret = Uri.encodeComponent(RoutePaths.plans);
        if (mounted) {
          context.go('${RoutePaths.billingInfo}?return=$ret');
        }
        return;
      }

      // Navega a la pantalla embedded — el widget Stripe se monta dentro
      // de nuestra app (no redirect). La pantalla embedded se encarga de
      // crear la session y montar el widget.
      //
      // Si hay un código promocional aplicado, lo pasamos como query param
      // para que la pantalla embedded lo incluya en el create-session.
      final period = widget.yearly ? 'yearly' : 'monthly';
      final applied = ref.read(appliedPromotionCodeProvider);
      final promo = applied != null &&
              (applied.appliesToPlanSlugs == null ||
                  applied.appliesToPlanSlugs!.contains(widget.plan.slug))
          ? '&stripe_promotion_code_id=${Uri.encodeQueryComponent(applied.stripePromotionCodeId)}'
          : '';
      if (mounted) {
        context.go(
          '${RoutePaths.embeddedCheckout}'
          '?plan_slug=${widget.plan.slug}'
          '&billing_period=$period'
          '$promo',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
