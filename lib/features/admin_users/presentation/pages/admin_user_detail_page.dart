import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../application/admin_users_providers.dart';
import '../../domain/admin_user.dart';
import '../widgets/change_plan_dialog.dart';
import '../widgets/user_status_chip.dart';

/// `/admin/users/<id>` — detalle de un user. Cabecera con avatar +
/// estado, métricas en cards, secciones (profile / suscripción /
/// counters). Las acciones (block/deactivate/send_email/change_plan)
/// se invocan desde el botón de acciones en el AppBar.
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
          constraints: const BoxConstraints(maxWidth: 880),
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
      padding: const EdgeInsets.all(20),
      children: [
        // ─── Header card ───
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _bestDisplayName(detail),
                              style:
                                  context.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
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
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (detail.profile.role == 'admin')
                            _SmallChip(
                              label: l.adminUsersRoleAdmin,
                              color: context.colors.tertiary,
                            ),
                          _SmallChip(
                            label: detail.profile.locale.toUpperCase(),
                            color: context.colors.onSurfaceVariant,
                          ),
                          if (detail.emailConfirmedAt != null)
                            _SmallChip(
                              label: l.adminUserDetailEmailVerified,
                              color: context.colors.primary,
                            )
                          else
                            _SmallChip(
                              label: l.adminUserDetailEmailUnverified,
                              color: Colors.amber.shade800,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ─── Counters ───
        Wrap(
          spacing: 12,
          runSpacing: 12,
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
        const SizedBox(height: 16),
        // ─── Account info ───
        _Section(l.adminUserDetailAccountSection),
        Card(
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
        const SizedBox(height: 16),
        // ─── Subscription ───
        _Section(l.adminUserDetailSubscriptionSection),
        Card(
          child: detail.subscription == null
              ? Padding(
                  padding: const EdgeInsets.all(16),
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
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.swap_horiz),
            label: Text(l.adminUserDetailChangePlan),
            onPressed: () => _onChangePlan(context, ref),
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              k,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
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
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
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
      width: 180,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      value,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
