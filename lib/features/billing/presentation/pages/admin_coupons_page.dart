import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_pagination_bar.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.admin),
        ),
        title: Text(l.adminCouponsTitle),
      ),
      body: const AdminCouponsView(),
    );
  }
}

/// Cuerpo del catálogo de cupones (sin Scaffold). Reutilizable como página
/// completa o embebido en el master-detail de Administración.
///
/// El botón de crear (antes un FAB del Scaffold) se reposiciona dentro del
/// panel.
class AdminCouponsView extends ConsumerStatefulWidget {
  const AdminCouponsView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Admin).
  final bool embedded;

  @override
  ConsumerState<AdminCouponsView> createState() => _AdminCouponsViewState();
}

class _AdminCouponsViewState extends ConsumerState<AdminCouponsView> {
  int _page = 0;
  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final listAsync = ref.watch(adminCouponsListProvider);
    final plansAsync = ref.watch(plansProvider);

    final content = listAsync.when(
      loading: () => const AppLoadingState(),
      error: (e, _) => AppErrorState(
        message: l.adminCouponsLoadError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(adminCouponsListProvider),
        retryLabel: l.actionRetry,
      ),
      data: (data) {
        if (data.coupons.isEmpty) {
          return AppEmptyState(
            icon: Icons.local_offer_outlined,
            message: l.adminCouponsEmpty,
          );
        }
        // Agrupamos los promotion_codes por coupon_id para pintar.
        final byCoupon = <String, List<PromotionCode>>{};
        for (final pc in data.promotionCodes) {
          byCoupon.putIfAbsent(pc.couponId, () => []).add(pc);
        }
        final coupons = data.coupons;
        final totalPages = (coupons.length / _pageSize).ceil();
        final page = _page.clamp(0, totalPages - 1);
        final start = page * _pageSize;
        final end = (start + _pageSize) > coupons.length
            ? coupons.length
            : start + _pageSize;
        final pageCoupons = coupons.sublist(start, end);
        final list = ListView.separated(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            widget.embedded ? AppSpacing.md : 96,
          ),
          shrinkWrap: widget.embedded,
          physics:
              widget.embedded ? const NeverScrollableScrollPhysics() : null,
          itemCount: pageCoupons.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) {
            final c = pageCoupons[i];
            return _CouponCard(
              coupon: c,
              codes: byCoupon[c.id] ?? const [],
            );
          },
        );
        return Column(
          mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (widget.embedded) list else Expanded(child: list),
            AppPaginationBar(
              currentPage: page,
              totalPages: totalPages,
              onPrevious: () => setState(() => _page = page - 1),
              onNext: () => setState(() => _page = page + 1),
            ),
          ],
        );
      },
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
        child: Column(
          mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // Acciones del panel (antes refresh en AppBar + FAB de crear).
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: l.actionRetry,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.invalidate(adminCouponsListProvider),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: () => _onCreateCoupon(plansAsync.valueOrNull),
                    icon: const Icon(Icons.add),
                    label: Text(l.adminCouponsCreate),
                  ),
                ],
              ),
            ),
            if (widget.embedded) content else Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Future<void> _onCreateCoupon(List<Plan>? plans) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) =>
          AdminCouponCreateDialog(availablePlans: plans ?? const []),
    );
    if ((created ?? false) && mounted) {
      ref.invalidate(adminCouponsListProvider);
    }
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
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
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
                              decoration:
                                  inactive ? TextDecoration.lineThrough : null,
                              color: inactive
                                  ? context.colors.onSurfaceVariant
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        PremiumBadge(
                          label: coupon.formatDiscount(),
                          variant: PremiumBadgeVariant.info,
                          dense: true,
                        ),
                        if (inactive) ...[
                          const SizedBox(width: AppSpacing.sm),
                          PremiumBadge(
                            label: l.adminCouponsInactive,
                            variant: PremiumBadgeVariant.error,
                            dense: true,
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
    final confirm = await AppConfirmDialog.show(
      context,
      title: l.adminCouponsDeactivateConfirmTitle,
      body: l.adminCouponsDeactivateConfirmBody(coupon.name),
      confirmLabel: l.adminCouponsDeactivate,
      cancelLabel: l.actionCancel,
      danger: true,
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
                decoration:
                    inactive || expired ? TextDecoration.lineThrough : null,
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
