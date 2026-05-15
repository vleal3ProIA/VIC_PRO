import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';

import '../../application/team_providers.dart';
import '../../application/tenant_providers.dart';
import '../../domain/tenant.dart';
import '../../domain/tenant_invitation.dart';
import '../../domain/tenant_member.dart';
import '../../domain/tenant_member_profile.dart';
import '../widgets/invite_member_dialog.dart';

/// Pantalla `/team` — gestión del workspace activo: miembros + invitaciones.
///
/// Visibilidad por rol:
///   - **member**: ve la lista de miembros (read-only). No ve invitaciones.
///   - **admin/owner**: ve TODO + acciones (invitar, cambiar rol, remove,
///     revocar invitaciones).
class TeamPage extends ConsumerWidget {
  const TeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final tenant = ref.watch(currentTenantProvider).valueOrNull;
    final membersAsync = ref.watch(currentTenantMembersProvider);
    final invitationsAsync = ref.watch(currentTenantInvitationsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.accountSettings),
        ),
        title: Text(l.teamTitle),
        actions: [
          if (tenant != null && _canInvite(ref))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: () => _onInvite(context, ref, tenant),
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: Text(l.teamInviteAction),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              // ── Miembros ──────────────────────────────────────────
              _SectionHeader(label: l.teamMembersSection),
              membersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => _ErrorBox(message: l.teamErrorGeneric),
                data: (members) {
                  if (members.isEmpty) {
                    return _EmptyBox(message: l.teamEmptyMembers);
                  }
                  return Card(
                    child: Column(
                      children: [
                        for (final m in members)
                          _MemberTile(
                            member: m,
                            canManage: _canManage(ref, m),
                            isSelf: m.userId == _currentUserId(ref),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),

              // ── Invitaciones pendientes (solo admin) ──────────────
              if (_canInvite(ref))
                invitationsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (invitations) {
                    final pending =
                        invitations.where((inv) => inv.isPending).toList();
                    if (pending.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(label: l.teamInvitationsSection),
                        Card(
                          child: Column(
                            children: [
                              for (final inv in pending)
                                _InvitationTile(invitation: inv),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers de autorización ────────────────────────────────────────────

  bool _canInvite(WidgetRef ref) {
    final me = _myMembership(ref);
    return me != null && me.role.isAdmin;
  }

  bool _canManage(WidgetRef ref, TenantMemberProfile target) {
    final me = _myMembership(ref);
    if (me == null) return false;
    if (!me.role.isAdmin) return false;
    // Nadie (ni un owner) puede tocar a otro owner desde aquí — transferir
    // ownership es flujo aparte.
    if (target.role == TenantRole.owner) return false;
    return true;
  }

  TenantMember? _myMembership(WidgetRef ref) {
    final myId = _currentUserId(ref);
    if (myId == null) return null;
    final members =
        ref.read(currentTenantMembersProvider).valueOrNull ?? const [];
    for (final m in members) {
      if (m.userId == myId) {
        return TenantMember(
          tenantId: m.tenantId,
          userId: m.userId,
          role: m.role,
          joinedAt: m.joinedAt,
        );
      }
    }
    return null;
  }

  String? _currentUserId(WidgetRef ref) =>
      ref.read(supabaseClientProvider).auth.currentUser?.id;

  // ── Acciones ───────────────────────────────────────────────────────────

  Future<void> _onInvite(
    BuildContext context,
    WidgetRef ref,
    Tenant tenant,
  ) async {
    final result = await showDialog<CreatedInvitation>(
      context: context,
      builder: (_) => InviteMemberDialog(tenant: tenant),
    );
    if (result == null || !context.mounted) return;
    // Mostramos el enlace al admin para que lo copie. Se ve UNA vez.
    final url = _buildInviteUrl(result.token);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InviteCreatedDialog(url: url),
    );
  }

  String _buildInviteUrl(String token) {
    // El frontend conoce la URL canónica vía Uri.base (en web).
    final base = Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort && base.port != 80 && base.port != 443 ? base.port : null,
      path: RoutePaths.acceptInvite,
      queryParameters: {'token': token},
    ).toString();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          label,
          style: context.textTheme.titleSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            message,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(message, style: TextStyle(color: context.colors.error)),
        ),
      );
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.member,
    required this.canManage,
    required this.isSelf,
  });
  final TenantMemberProfile member;
  final bool canManage;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.colors.primaryContainer,
        child: Text(
          member.initials(),
          style: TextStyle(color: context.colors.onPrimaryContainer),
        ),
      ),
      title: Text(member.displayLabel()),
      subtitle: member.email != null && member.email != member.displayLabel()
          ? Text(member.email!)
          : null,
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _RoleChip(role: member.role),
          if (isSelf && member.role != TenantRole.owner)
            TextButton(
              onPressed: () => _onLeave(context, ref),
              child: Text(l.teamMemberLeave),
            )
          else if (canManage)
            IconButton(
              tooltip: l.teamMemberMenuRemove,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => _onRemove(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _onRemove(BuildContext context, WidgetRef ref) async {
    final ds = ref.read(tenantDataSourceProvider);
    try {
      await ds.removeMember(
        tenantId: member.tenantId,
        userId: member.userId,
      );
      ref.invalidate(currentTenantMembersProvider);
    } catch (_) {
      if (!context.mounted) return;
      context.showSnack(context.l10n.teamErrorGeneric, isError: true);
    }
  }

  Future<void> _onLeave(BuildContext context, WidgetRef ref) async {
    final ds = ref.read(tenantDataSourceProvider);
    try {
      await ds.leave(member.tenantId);
      ref
        ..invalidate(myTenantsProvider)
        ..invalidate(currentTenantMembersProvider);
    } catch (_) {
      if (!context.mounted) return;
      context.showSnack(context.l10n.teamErrorGeneric, isError: true);
    }
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final TenantRole role;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final label = switch (role) {
      TenantRole.owner => l.teamMemberRoleOwner,
      TenantRole.admin => l.teamMemberRoleAdmin,
      TenantRole.member => l.teamMemberRoleMember,
    };
    final bg = role == TenantRole.owner
        ? context.colors.primaryContainer
        : context.colors.surfaceContainerHigh;
    return Chip(
      label: Text(label),
      backgroundColor: bg,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _InvitationTile extends ConsumerWidget {
  const _InvitationTile({required this.invitation});
  final TenantInvitation invitation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final formatter = DateFormat.yMMMd(localeCode);
    return ListTile(
      leading: const Icon(Icons.mail_outline),
      title: Text(invitation.email),
      subtitle: Text(
        l.teamInvitationExpiresIn(formatter.format(invitation.expiresAt)),
      ),
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _RoleChip(role: invitation.role),
          IconButton(
            tooltip: l.teamInvitationRevoke,
            icon: const Icon(Icons.cancel_outlined),
            onPressed: () async {
              try {
                await revokeInvitation(ref, invitation.id);
              } catch (_) {
                if (!context.mounted) return;
                context.showSnack(context.l10n.teamErrorGeneric, isError: true);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Modal que se muestra inmediatamente tras crear una invitación, con el
/// enlace plaintext. Es la **única vez** que el admin puede ver el token —
/// la BD solo guarda el hash.
class _InviteCreatedDialog extends StatelessWidget {
  const _InviteCreatedDialog({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.teamInviteCreatedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.teamInviteCreatedHint(_emailFromUrl(url)),
            style: context.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SelectableText(
            url,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) return;
            context.showSnack(context.l10n.teamInviteLinkCopied);
          },
          label: Text(l.teamInviteCopyLink),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }

  /// El email viaja en el dialog precedente (InviteMemberDialog), pero
  /// aquí no lo tenemos; podríamos pasarlo. Por simplicidad solo
  /// mostramos un genérico — el admin lo escribió hace segundos.
  String _emailFromUrl(String _) => '...';
}
