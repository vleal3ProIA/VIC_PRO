import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../application/admin_users_providers.dart';
import '../../domain/admin_user.dart';
import '../widgets/send_user_email_dialog.dart';
import '../widgets/user_status_chip.dart';

/// `/admin/users` — gestión de usuarios. KPIs cards arriba, tabla
/// paginada con filtros y acciones por fila. Las acciones invocan la
/// Edge Function `admin-users`.
class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(adminUsersQueryProvider.notifier).update(
            (q) => q.copyWith(search: v, offset: 0),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final query = ref.watch(adminUsersQueryProvider);
    final kpisAsync = ref.watch(adminUsersKpisProvider);
    final pageAsync = ref.watch(adminUsersPageProvider(query));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.admin),
        ),
        title: Text(l.adminUsersTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref
                ..invalidate(adminUsersKpisProvider)
                ..invalidate(adminUsersPageProvider);
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              // ─── KPIs cards ───
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: kpisAsync.when(
                  loading: () => const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (k) => _KpisRow(kpis: k),
                ),
              ),
              // ─── Filtros ───
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _FiltersRow(
                  searchCtrl: _searchCtrl,
                  onSearchChanged: _onSearchChanged,
                  query: query,
                  kpis: kpisAsync.valueOrNull,
                ),
              ),
              const SizedBox(height: 8),
              // ─── Tabla ───
              Expanded(
                child: pageAsync.when(
                  loading: () => const AppLoadingState(),
                  error: (e, _) => AppErrorState(
                    message: l.adminUsersLoadError,
                    detail: e.toString(),
                    onRetry: () => ref.invalidate(adminUsersPageProvider),
                    retryLabel: l.actionRetry,
                  ),
                  data: (page) {
                    if (page.rows.isEmpty) {
                      return AppEmptyState(
                        icon: Icons.people_outline,
                        title: l.adminUsersEmptyTitle,
                        message: l.adminUsersEmptyBody,
                      );
                    }
                    return _UsersTable(page: page, query: query);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── KPIs cards ───────────────────────

class _KpisRow extends StatelessWidget {
  const _KpisRow({required this.kpis});
  final AdminUsersKpis kpis;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _KpiCard(
          icon: Icons.people,
          label: l.adminUsersKpiTotal,
          value: kpis.totalUsers.toString(),
          subtitle: l.adminUsersKpiSignups30d(kpis.signups30d),
        ),
        _KpiCard(
          icon: Icons.check_circle,
          label: l.adminUsersStatusActive,
          value: kpis.statusCount(UserStatus.active).toString(),
          subtitle: '',
          color: Theme.of(context).colorScheme.primary,
        ),
        _KpiCard(
          icon: Icons.timer_outlined,
          label: l.adminUsersStatusBlocked,
          value: kpis.statusCount(UserStatus.blocked).toString(),
          subtitle: '',
          color: Colors.amber.shade800,
        ),
        _KpiCard(
          icon: Icons.block,
          label: l.adminUsersStatusDeactivated,
          value: kpis.statusCount(UserStatus.deactivated).toString(),
          subtitle: '',
          color: Theme.of(context).colorScheme.error,
        ),
        if (kpis.byPlan.isNotEmpty)
          _PlansBreakdownCard(plans: kpis.byPlan),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.onSurface;
    return SizedBox(
      width: 180,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: c),
              ),
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
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
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

class _PlansBreakdownCard extends StatelessWidget {
  const _PlansBreakdownCard({required this.plans});
  final List<PlanCount> plans;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SizedBox(
      width: 280,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.adminUsersKpiByPlan,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final p in plans)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          style: context.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        p.count.toString(),
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
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

// ─────────────────────── Filtros ───────────────────────

class _FiltersRow extends ConsumerWidget {
  const _FiltersRow({
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.query,
    required this.kpis,
  });
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final AdminUsersQuery query;
  final AdminUsersKpis? kpis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: searchCtrl,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: l.adminUsersSearchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        DropdownButton<String>(
          value: query.status,
          onChanged: (v) {
            if (v == null) return;
            ref
                .read(adminUsersQueryProvider.notifier)
                .update((q) => q.copyWith(status: v, offset: 0));
          },
          items: [
            DropdownMenuItem(value: 'all', child: Text(l.adminUsersFilterAll)),
            DropdownMenuItem(
              value: 'active',
              child: Text(l.adminUsersStatusActive),
            ),
            DropdownMenuItem(
              value: 'blocked',
              child: Text(l.adminUsersStatusBlocked),
            ),
            DropdownMenuItem(
              value: 'deactivated',
              child: Text(l.adminUsersStatusDeactivated),
            ),
          ],
        ),
        if (kpis != null && kpis!.byPlan.isNotEmpty)
          DropdownButton<String>(
            value: query.planSlug,
            onChanged: (v) {
              if (v == null) return;
              ref
                  .read(adminUsersQueryProvider.notifier)
                  .update((q) => q.copyWith(planSlug: v, offset: 0));
            },
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(l.adminUsersFilterAllPlans),
              ),
              for (final p in kpis!.byPlan)
                DropdownMenuItem(value: p.slug, child: Text(p.name)),
            ],
          ),
      ],
    );
  }
}

// ─────────────────────── Tabla ───────────────────────

class _UsersTable extends ConsumerWidget {
  const _UsersTable({required this.page, required this.query});
  final AdminUsersListResult page;
  final AdminUsersQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: page.rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) => _UserRow(user: page.rows[i]),
          ),
        ),
        // Paginación.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l.adminUsersPreviousPage,
                icon: const Icon(Icons.chevron_left),
                onPressed: query.offset > 0
                    ? () => ref.read(adminUsersQueryProvider.notifier).update(
                          (q) => q.copyWith(
                            offset: (q.offset - q.limit).clamp(0, 1 << 30),
                          ),
                        )
                    : null,
              ),
              Text(
                l.adminUsersPageOf(
                  (query.offset ~/ query.limit) + 1,
                  ((page.totalCount + query.limit - 1) ~/ query.limit)
                      .clamp(1, 1 << 30),
                  page.totalCount,
                ),
                style: context.textTheme.bodySmall,
              ),
              IconButton(
                tooltip: l.adminUsersNextPage,
                icon: const Icon(Icons.chevron_right),
                onPressed: (query.offset + query.limit) < page.totalCount
                    ? () => ref.read(adminUsersQueryProvider.notifier).update(
                          (q) => q.copyWith(offset: q.offset + q.limit),
                        )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserRow extends ConsumerStatefulWidget {
  const _UserRow({required this.user});
  final AdminUserSummary user;

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode);
    final u = widget.user;
    final currentUser = ref.watch(currentUserProvider);
    final isSelf = currentUser?.id == u.id;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.goNamed(
          RouteNames.adminUserDetail,
          pathParameters: {'id': u.id},
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: (u.avatarUrl?.isNotEmpty ?? false)
                    ? NetworkImage(u.avatarUrl!)
                    : null,
                child: (u.avatarUrl?.isNotEmpty ?? false)
                    ? null
                    : Text(
                        (u.email.isNotEmpty ? u.email[0] : '?').toUpperCase(),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            u.bestDisplayName,
                            style: context.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        UserStatusChip(status: u.status),
                        if (u.isAdmin) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.tertiary
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l.adminUsersRoleAdmin,
                              style: context.textTheme.labelSmall?.copyWith(
                                color: context.colors.tertiary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      u.email,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          u.currentPlanName,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '·',
                          style: TextStyle(color: context.colors.onSurfaceVariant),
                        ),
                        Text(
                          u.locale.toUpperCase(),
                          style: context.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '·',
                          style: TextStyle(color: context.colors.onSurfaceVariant),
                        ),
                        Text(
                          l.adminUsersSignedUp(fmt.format(u.signedUpAt.toLocal())),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_busy,
                tooltip: l.adminUsersActions,
                onSelected: (v) async {
                  switch (v) {
                    case 'open':
                      context.goNamed(
                        RouteNames.adminUserDetail,
                        pathParameters: {'id': u.id},
                      );
                    case 'send_email':
                      await _onSendEmail();
                    case 'block':
                      await _onBlock();
                    case 'unblock':
                      await _onUnblock();
                    case 'deactivate':
                      await _onDeactivate();
                    case 'reactivate':
                      await _onReactivate();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'open',
                    child: Row(
                      children: [
                        const Icon(Icons.open_in_new, size: 18),
                        const SizedBox(width: 8),
                        Text(l.adminUsersOpenDetail),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'send_email',
                    child: Row(
                      children: [
                        const Icon(Icons.mail_outline, size: 18),
                        const SizedBox(width: 8),
                        Text(l.adminUsersSendEmail),
                      ],
                    ),
                  ),
                  if (!isSelf) ...[
                    if (u.status == UserStatus.active)
                      PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(l.adminUsersBlockTemporary),
                          ],
                        ),
                      )
                    else if (u.status == UserStatus.blocked)
                      PopupMenuItem(
                        value: 'unblock',
                        child: Row(
                          children: [
                            const Icon(Icons.lock_open, size: 18),
                            const SizedBox(width: 8),
                            Text(l.adminUsersUnblock),
                          ],
                        ),
                      ),
                    if (u.status != UserStatus.deactivated)
                      PopupMenuItem(
                        value: 'deactivate',
                        child: Row(
                          children: [
                            Icon(
                              Icons.block,
                              size: 18,
                              color: context.colors.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l.adminUsersDeactivate,
                              style: TextStyle(color: context.colors.error),
                            ),
                          ],
                        ),
                      )
                    else
                      PopupMenuItem(
                        value: 'reactivate',
                        child: Row(
                          children: [
                            const Icon(Icons.restart_alt, size: 18),
                            const SizedBox(width: 8),
                            Text(l.adminUsersReactivate),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _withBusy(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidateAll() {
    ref
      ..invalidate(adminUsersKpisProvider)
      ..invalidate(adminUsersPageProvider);
  }

  Future<void> _onSendEmail() async {
    final l = context.l10n;
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SendUserEmailDialog(user: widget.user),
    );
    if ((sent ?? false) && mounted) {
      context.showSnack(l.adminUsersEmailSent);
    }
  }

  Future<void> _onBlock() async {
    final l = context.l10n;
    final until = await _pickBlockUntil();
    if (until == null) return;
    await _withBusy(() async {
      final result = await ref
          .read(adminUsersDataSourceProvider)
          .block(userId: widget.user.id, until: until);
      if (!mounted) return;
      if (result.ok) {
        _invalidateAll();
        context.showSnack(l.adminUsersBlocked);
      } else {
        context.showSnack(
          l.adminUsersActionFailed(result.error ?? '?'),
          isError: true,
        );
      }
    });
  }

  Future<void> _onUnblock() async {
    final l = context.l10n;
    await _withBusy(() async {
      final result = await ref
          .read(adminUsersDataSourceProvider)
          .unblock(widget.user.id);
      if (!mounted) return;
      if (result.ok) {
        _invalidateAll();
        context.showSnack(l.adminUsersUnblocked);
      } else {
        context.showSnack(
          l.adminUsersActionFailed(result.error ?? '?'),
          isError: true,
        );
      }
    });
  }

  Future<void> _onDeactivate() async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.adminUsersDeactivateConfirmTitle,
      body: l.adminUsersDeactivateConfirmBody(widget.user.email),
      confirmLabel: l.adminUsersDeactivate,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true) return;
    await _withBusy(() async {
      final result = await ref
          .read(adminUsersDataSourceProvider)
          .deactivate(widget.user.id);
      if (!mounted) return;
      if (result.ok) {
        _invalidateAll();
        context.showSnack(l.adminUsersDeactivated);
      } else {
        context.showSnack(
          l.adminUsersActionFailed(result.error ?? '?'),
          isError: true,
        );
      }
    });
  }

  Future<void> _onReactivate() async {
    final l = context.l10n;
    await _withBusy(() async {
      final result = await ref
          .read(adminUsersDataSourceProvider)
          .reactivate(widget.user.id);
      if (!mounted) return;
      if (result.ok) {
        _invalidateAll();
        context.showSnack(l.adminUsersReactivated);
      } else {
        context.showSnack(
          l.adminUsersActionFailed(result.error ?? '?'),
          isError: true,
        );
      }
    });
  }

  Future<DateTime?> _pickBlockUntil() async {
    final l = context.l10n;
    // 5 presets: 1h, 24h, 7d, 30d, 90d. Custom date picker fallback.
    final picked = await showModalBottomSheet<Duration>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l.adminUsersBlock1h),
              onTap: () =>
                  Navigator.of(context).pop(const Duration(hours: 1)),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l.adminUsersBlock24h),
              onTap: () =>
                  Navigator.of(context).pop(const Duration(hours: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l.adminUsersBlock7d),
              onTap: () =>
                  Navigator.of(context).pop(const Duration(days: 7)),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l.adminUsersBlock30d),
              onTap: () =>
                  Navigator.of(context).pop(const Duration(days: 30)),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l.adminUsersBlock90d),
              onTap: () =>
                  Navigator.of(context).pop(const Duration(days: 90)),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return null;
    return DateTime.now().add(picked);
  }
}
