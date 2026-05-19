import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/admin_users_providers.dart';
import '../../domain/admin_user.dart';
import '../widgets/change_plan_dialog.dart';
import '../widgets/user_status_chip.dart';

/// `/admin/users/<id>` — detalle de un user.
///
/// **Rediseno Premium UI Fase 12**: cabecera con avatar + UserStatusChip
/// + PremiumBadges para role/locale/email-verified; 4 _CounterCards en
/// PremiumCard; secciones (Account / Subscription) con SectionHeader
/// + key-value lists en PremiumCard. Mantiene toda la logica
/// (change_plan dialog, providers invalidation, mapping de campos).
class AdminUserDetailPage extends ConsumerWidget {
  const AdminUserDetailPage({required this.userId, super.key});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(adminUserDetailProvider(userId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.adminUsers),
        ),
        title: Text(l.adminUserDetailTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(adminUserDetailProvider(userId)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
          child: async.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.adminUserDetailLoadError,
              detail: e.toString(),
              onRetry: () =>
                  ref.invalidate(adminUserDetailProvider(userId)),
              retryLabel: l.actionRetry,
            ),
            data: (detail) => _Body(detail: detail),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});
  final AdminUserDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // ─── Header card ───
        PremiumCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage:
                    (detail.profile.avatarUrl?.isNotEmpty ?? false)
                        ? NetworkImage(detail.profile.avatarUrl!)
                        : null,
                child: (detail.profile.avatarUrl?.isNotEmpty ?? false)
                    ? null
                    : Text(
                        (detail.email.isNotEmpty ? detail.email[0] : '?')
                            .toUpperCase(),
                        style: const TextStyle(fontSize: 24),
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _bestDisplayName(detail),
                            style: context.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        UserStatusChip(status: detail.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      detail.email,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: 4,
                      children: [
                        if (detail.profile.role == 'admin')
                          PremiumBadge(
                            label: l.adminUsersRoleAdmin,
                            variant: PremiumBadgeVariant.info,
                            dense: true,
                          ),
                        PremiumBadge(
                          label: detail.profile.locale.toUpperCase(),
                          variant: PremiumBadgeVariant.neutral,
                          dense: true,
                        ),
                        if (detail.emailConfirmedAt != null)
                          PremiumBadge(
                            label: l.adminUserDetailEmailVerified,
                            variant: PremiumBadgeVariant.success,
                            icon: Icons.check_circle,
                            dense: true,
                          )
                        else
                          PremiumBadge(
                            label: l.adminUserDetailEmailUnverified,
                            variant: PremiumBadgeVariant.warning,
                            icon: Icons.warning_amber_rounded,
                            dense: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // ─── Counters ───
        Wrap(
          spacing: AppSpacing.sm + 4,
          runSpacing: AppSpacing.sm + 4,
          children: [
            _CounterCard(
              icon: Icons.devices_outlined,
              label: l.adminUserDetailSessions,
              value: detail.sessionsCount.toString(),
            ),
            _CounterCard(
              icon: Icons.vpn_key_outlined,
              label: l.adminUserDetailActiveTokens,
              value: detail.activeTokensCount.toString(),
            ),
            _CounterCard(
              icon: Icons.groups_outlined,
              label: l.adminUserDetailTenants,
              value: detail.tenantsCount.toString(),
            ),
            _CounterCard(
              icon: Icons.mail_outline,
              label: l.adminUserDetailEmailsSent,
              value: detail.emailsSentCount.toString(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // ─── Account info ───
        _Section(l.adminUserDetailAccountSection),
        PremiumCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _kv(
                context,
                l.adminUserDetailUserId,
                detail.id,
                mono: true,
              ),
              const Divider(height: 1),
              _kv(
                context,
                l.adminUserDetailSignedUp,
                fmt.format(detail.createdAt.toLocal()),
              ),
              const Divider(height: 1),
              _kv(
                context,
                l.adminUserDetailLastSignIn,
                detail.lastSignInAt != null
                    ? fmt.format(detail.lastSignInAt!.toLocal())
                    : l.adminUserDetailNever,
              ),
              if (detail.status == UserStatus.blocked &&
                  detail.bannedUntil != null) ...[
                const Divider(height: 1),
                _kv(
                  context,
                  l.adminUserDetailBlockedUntil,
                  fmt.format(detail.bannedUntil!.toLocal()),
                  color: Colors.amber.shade800,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // ─── Subscription ───
        _Section(l.adminUserDetailSubscriptionSection),
        PremiumCard(
          padding: EdgeInsets.zero,
          child: detail.subscription == null
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    l.adminUserDetailNoSubscription,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  children: [
                    _kv(
                      context,
                      l.adminUserDetailPlan,
                      detail.subscription!.planName,
                    ),
                    const Divider(height: 1),
                    _kv(
                      context,
                      l.adminUserDetailSubStatus,
                      detail.subscription!.status,
                    ),
                    if (detail.subscription!.currentPeriodEnd != null) ...[
                      const Divider(height: 1),
                      _kv(
                        context,
                        l.adminUserDetailPeriodEnd,
                        fmt.format(
                          detail.subscription!.currentPeriodEnd!.toLocal(),
                        ),
                      ),
                    ],
                    if (detail.subscription!.stripeCustomerId != null) ...[
                      const Divider(height: 1),
                      _kv(
                        context,
                        l.adminUserDetailStripeCustomerId,
                        detail.subscription!.stripeCustomerId!,
                        mono: true,
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: PremiumButton(
            label: l.adminUserDetailChangePlan,
            variant: PremiumButtonVariant.secondary,
            size: PremiumButtonSize.sm,
            leadingIcon: Icons.swap_horiz,
            onPressed: () => _onChangePlan(context, ref),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Future<void> _onChangePlan(BuildContext context, WidgetRef ref) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ChangePlanDialog(userId: detail.id),
    );
    if (changed ?? false) {
      ref
        ..invalidate(adminUserDetailProvider(detail.id))
        ..invalidate(adminUsersKpisProvider)
        ..invalidate(adminUsersPageProvider);
    }
  }

  String _bestDisplayName(AdminUserDetail d) {
    final fl = [d.profile.firstName, d.profile.lastName]
        .whereType<String>()
        .join(' ')
        .trim();
    if (fl.isNotEmpty) return fl;
    if (d.profile.displayName?.isNotEmpty ?? false) {
      return d.profile.displayName!;
    }
    if (d.profile.username?.isNotEmpty ?? false) return d.profile.username!;
    return d.email;
  }

  Widget _kv(
    BuildContext context,
    String k,
    String v, {
    bool mono = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              k,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: context.textTheme.bodyMedium?.copyWith(
                color: color,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: context.textTheme.labelMedium?.copyWith(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: PremiumCard(
        padding: const EdgeInsets.all(AppSpacing.sm + 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.12),
                borderRadius: AppRadii.brSm,
              ),
              child: Icon(icon, color: context.colors.primary),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    value,
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
