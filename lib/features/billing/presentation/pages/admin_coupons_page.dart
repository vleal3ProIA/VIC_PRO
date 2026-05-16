import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/admin_coupons_providers.dart';
import '../../application/billing_providers.dart';
import '../../data/admin_coupons_datasource.dart';
import '../../domain/coupon.dart';
import '../../domain/plan.dart';
import '../../domain/promotion_code.dart';
import '../widgets/admin_coupon_create_dialog.dart';
import '../widgets/admin_promotion_code_create_dialog.dart';

/// `/admin/coupons` — catálogo de cupones + códigos promocionales.
/// Cualquier mutación pasa por la Edge Function `admin-coupons` (sync
/// con Stripe Coupons/PromotionCodes API).
class AdminCouponsPage extends ConsumerWidget {
  const AdminCouponsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final listAsync = ref.watch(adminCouponsListProvider);
    final plansAsync = ref.watch(plansProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.admin),
        ),
        title: Text(l.adminCouponsTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminCouponsListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.adminCouponsCreate),
        onPressed: () => _onCreateCoupon(context, ref, plansAsync.valueOrNull),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: listAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                l.adminCouponsLoadError,
                style: TextStyle(color: context.colors.error),
              ),
            ),
            data: (data) {
              if (data.coupons.isEmpty) {
                return _Empty(message: l.adminCouponsEmpty);
              }
              // Agrupamos los promotion_codes por coupon_id para pintar.
              final byCoupon = <String, List<PromotionCode>>{};
              for (final pc in data.promotionCodes) {
                byCoupon.putIfAbsent(pc.couponId, () => []).add(pc);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: data.coupons.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = data.coupons[i];
                  return _CouponCard(
                    coupon: c,
                    codes: byCoupon[c.id] ?? const [],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onCreateCoupon(
    BuildContext context,
    WidgetRef ref,
    List<Plan>? plans,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) =>
          AdminCouponCreateDialog(availablePlans: plans ?? const []),
    );
    if ((created ?? false) && context.mounted) {
      ref.invalidate(adminCouponsListProvider);
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_offer_outlined,
            size: 48,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CouponCard extends ConsumerWidget {
  const _CouponCard({required this.coupon, required this.codes});
  final Coupon coupon;
  final List<PromotionCode> codes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final inactive = !coupon.isActive;
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
                          Flexible(
                            child: Text(
                              coupon.name,
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
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(coupon.formatDiscount()),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide.none,
                            backgroundColor: context.colors.primaryContainer,
                          ),
                          if (inactive) ...[
                            const SizedBox(width: 8),
                            Chip(
                              label: Text(l.adminCouponsInactive),
                              visualDensity: VisualDensity.compact,
                              side: BorderSide.none,
                              backgroundColor: context.colors.errorContainer,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _summary(context, coupon),
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!inactive)
                  IconButton(
                    tooltip: l.adminCouponsDeactivate,
                    icon: const Icon(Icons.block_outlined),
                    onPressed: () => _onDeactivateCoupon(context, ref),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.adminCouponsCodesLabel,
                    style: context.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!inactive)
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l.adminCouponsAddCode),
                    onPressed: () => _onCreatePromotionCode(context, ref),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (codes.isEmpty)
              Text(
                l.adminCouponsNoCodes,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              )
            else
              ...codes.map((pc) => _PromotionCodeRow(promo: pc)),
          ],
        ),
      ),
    );
  }

  String _summary(BuildContext context, Coupon c) {
    final l = context.l10n;
    final parts = <String>[];
    switch (c.duration) {
      case CouponDuration.once:
        parts.add(l.adminCouponsDurationOnce);
      case CouponDuration.repeating:
        parts.add(l.adminCouponsDurationRepeatingN(c.durationInMonths ?? 0));
      case CouponDuration.forever:
        parts.add(l.adminCouponsDurationForever);
    }
    if (c.maxRedemptions != null) {
      parts.add(l.adminCouponsRedemptions(c.timesRedeemed, c.maxRedemptions!));
    } else {
      parts.add(l.adminCouponsRedemptionsUnlimited(c.timesRedeemed));
    }
    if (c.redeemBy != null) {
      parts.add(
        l.adminCouponsRedeemBy(
          '${c.redeemBy!.year}-${c.redeemBy!.month.toString().padLeft(2, '0')}-${c.redeemBy!.day.toString().padLeft(2, '0')}',
        ),
      );
    }
    if (c.appliesToPlanSlugs != null && c.appliesToPlanSlugs!.isNotEmpty) {
      parts.add(l.adminCouponsAppliesTo(c.appliesToPlanSlugs!.join(', ')));
    } else {
      parts.add(l.adminCouponsAppliesToAll);
    }
    return parts.join(' • ');
  }

  Future<void> _onDeactivateCoupon(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.adminCouponsDeactivateConfirmTitle),
        content: Text(l.adminCouponsDeactivateConfirmBody(coupon.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.adminCouponsDeactivate),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref
          .read(adminCouponsDataSourceProvider)
          .deactivateCoupon(coupon.id);
      if (!context.mounted) return;
      ref.invalidate(adminCouponsListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminCouponsDeactivated)),
      );
    } on AdminCouponException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(l, e.code, e.detail))),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminCouponsActionError)),
      );
    }
  }

  Future<void> _onCreatePromotionCode(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => AdminPromotionCodeCreateDialog(coupon: coupon),
    );
    if ((created ?? false) && context.mounted) {
      ref.invalidate(adminCouponsListProvider);
    }
  }

  String _friendlyError(AppLocalizations l, String code, String? detail) {
    if (detail != null && detail.isNotEmpty) return 'Stripe: $detail';
    return l.adminCouponsActionError;
  }
}

class _PromotionCodeRow extends ConsumerWidget {
  const _PromotionCodeRow({required this.promo});
  final PromotionCode promo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final inactive = !promo.isActive;
    final expired =
        promo.expiresAt != null && promo.expiresAt!.isBefore(DateTime.now());
    final meta = <String>[];
    if (promo.maxRedemptions != null) {
      meta.add(
        l.adminCouponsRedemptions(
          promo.timesRedeemed,
          promo.maxRedemptions!,
        ),
      );
    } else if (promo.timesRedeemed > 0) {
      meta.add(l.adminCouponsRedemptionsUnlimited(promo.timesRedeemed));
    }
    if (promo.expiresAt != null) {
      meta.add(
        l.adminCouponsExpires(
          '${promo.expiresAt!.year}-${promo.expiresAt!.month.toString().padLeft(2, '0')}-${promo.expiresAt!.day.toString().padLeft(2, '0')}',
        ),
      );
    }
    if (promo.firstTimeTransaction) {
      meta.add(l.adminCouponsFirstTimeOnly);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              promo.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                decoration: inactive || expired
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              meta.join(' • '),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          if (!inactive)
            IconButton(
              tooltip: l.adminCouponsCodeDeactivate,
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => _onDeactivateCode(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _onDeactivateCode(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    try {
      await ref
          .read(adminCouponsDataSourceProvider)
          .deactivatePromotionCode(promo.id);
      if (!context.mounted) return;
      ref.invalidate(adminCouponsListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminCouponsCodeDeactivated)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminCouponsActionError)),
      );
    }
  }
}
