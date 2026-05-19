// ============================================================================
// AdminAdminsPage · /admin/admins (PR-Super-A2)
// ----------------------------------------------------------------------------
// SOLO super admin. El router (`isSuperAdminRoute` + guard 2c) ya
// redirige a /admin a quien no sea super. Esta page asume super.
//
// **Que muestra**:
//   1. Lista de admins (incluido el super al top). Por cada admin:
//        - Email + displayName.
//        - Badge "Super admin" si lo es.
//        - 13 toggles (uno por capability) habilitados/deshabilitados
//          segun lo concedido. El super admin ve los suyos pero **NO**
//          se los puede tocar (visualmente bloqueados).
//        - Boton "Revoke admin role" (excepto en el super -- bloqueado).
//   2. Boton "Promote user to admin" arriba, que abre dialog para
//      introducir email del candidato.
//
// **Flujo de errores**:
//   - Lista falla -> AppErrorState con retry (invalida adminsListProvider).
//   - Promote falla (user not found / already admin / red) -> SnackBar.
//   - Toggle falla -> SnackBar + estado revertido (refrescamos lista).
//   - Revoke falla -> SnackBar + dialog cerrado.
//
// **Defensa en profundidad**: la UI no es el unico gate -- el servidor
// re-valida cada RPC con `is_super_admin()`. Si alguien hackeara
// localmente el `isSuperAdminProvider` para que devuelva true, la
// proxima llamada a las RPC saldra con PostgrestException.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/admin_acl_providers.dart';
import '../../data/admin_acl_datasource.dart';
import '../../domain/admin_capability.dart';
import '../../domain/admin_row.dart';

class AdminAdminsPage extends ConsumerWidget {
  const AdminAdminsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final adminsAsync = ref.watch(adminsListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.admin),
        ),
        title: Text(l.adminAdminsTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminsListProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
          child: adminsAsync.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.adminAdminsLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(adminsListProvider),
              retryLabel: l.actionRetry,
            ),
            data: (admins) => _LoadedView(admins: admins),
          ),
        ),
      ),
    );
  }
}

class _LoadedView extends ConsumerWidget {
  const _LoadedView({required this.admins});
  final List<AdminRow> admins;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: l.adminAdminsTitle,
            subtitle: l.adminAdminsSubtitle,
            actions: [
              PremiumButton(
                label: l.adminAdminsPromoteCta,
                leadingIcon: Icons.person_add_alt_1_rounded,
                onPressed: () => _showPromoteDialog(context, ref),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: PremiumCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l.adminAdminsInfoBanner,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AppSpacing.gapLg,
          if (admins.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AppEmptyState(
                icon: Icons.admin_panel_settings_outlined,
                title: l.adminAdminsEmptyTitle,
                message: l.adminAdminsEmptyBody,
              ),
            )
          else
            for (final a in admins) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _AdminCard(admin: a),
              ),
              AppSpacing.gapMd,
            ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

Future<void> _showPromoteDialog(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final emailCtrl = TextEditingController();
  String? errorText;
  bool loading = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text(l.adminAdminsPromoteDialogTitle),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.adminAdminsPromoteDialogBody,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  AppSpacing.gapMd,
                  PremiumInput(
                    label: l.adminAdminsPromoteEmailLabel,
                    controller: emailCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.alternate_email_rounded,
                    hintText: 'user@example.com',
                    errorText: errorText,
                    enabled: !loading,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: Text(
                  MaterialLocalizations.of(ctx).cancelButtonLabel,
                ),
              ),
              PremiumButton(
                label: l.adminAdminsPromoteConfirm,
                loading: loading,
                onPressed: loading
                    ? null
                    : () async {
                        final email = emailCtrl.text.trim();
                        if (email.isEmpty) {
                          setLocal(
                            () => errorText =
                                l.adminAdminsPromoteEmailRequired,
                          );
                          return;
                        }
                        setLocal(() {
                          loading = true;
                          errorText = null;
                        });
                        // Capturamos antes del await -- evita
                        // use_build_context_synchronously.
                        final navigator = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(ctx);
                        final ds = ref.read(adminAclDataSourceProvider);
                        try {
                          await ds.promoteToAdminByEmail(email);
                          ref.invalidate(adminsListProvider);
                          navigator.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                l.adminAdminsPromoteSuccess(email),
                              ),
                            ),
                          );
                        } on AdminAclException catch (e) {
                          setLocal(() {
                            loading = false;
                            errorText = _localizeError(l, e.code);
                          });
                        } catch (_) {
                          setLocal(() {
                            loading = false;
                            errorText = l.adminAdminsPromoteUnknownError;
                          });
                        }
                      },
              ),
            ],
          );
        },
      );
    },
  );
}

String _localizeError(AppLocalizations l, String code) {
  switch (code) {
    case 'user_not_found':
      return l.adminAdminsErrorUserNotFound;
    case 'already_admin':
      return l.adminAdminsErrorAlreadyAdmin;
    case 'super_only':
      return l.adminAdminsErrorSuperOnly;
    case 'email_required':
      return l.adminAdminsPromoteEmailRequired;
    case 'cannot_revoke_super':
      return l.adminAdminsErrorCannotRevokeSuper;
    case 'target_not_admin':
      return l.adminAdminsErrorTargetNotAdmin;
    default:
      return l.adminAdminsPromoteUnknownError;
  }
}

class _AdminCard extends ConsumerWidget {
  const _AdminCard({required this.admin});
  final AdminRow admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header (avatar + nombre + super badge + actions) ───
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                    scheme.primary.withValues(alpha: 0.12),
                child: Icon(
                  admin.isSuperAdmin
                      ? Icons.workspace_premium_rounded
                      : Icons.shield_outlined,
                  color: scheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            admin.bestDisplayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (admin.isSuperAdmin) ...[
                          const SizedBox(width: AppSpacing.sm),
                          PremiumBadge(
                            label: l.adminAdminsBadgeSuper,
                            variant: PremiumBadgeVariant.warning,
                            icon: Icons.workspace_premium_rounded,
                          ),
                        ],
                      ],
                    ),
                    if (admin.displayName != null &&
                        admin.displayName!.isNotEmpty &&
                        admin.email.isNotEmpty &&
                        admin.bestDisplayName != admin.email) ...[
                      const SizedBox(height: 2),
                      Text(
                        admin.email,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (!admin.isSuperAdmin)
                PremiumButton(
                  label: l.adminAdminsRevokeCta,
                  variant: PremiumButtonVariant.destructive,
                  size: PremiumButtonSize.sm,
                  leadingIcon: Icons.person_remove_alt_1_rounded,
                  onPressed: () => _onRevoke(context, ref, admin),
                ),
            ],
          ),
          AppSpacing.gapMd,
          Divider(
            height: 1,
            color: scheme.outline.withValues(alpha: 0.15),
          ),
          AppSpacing.gapMd,
          Text(
            l.adminAdminsCapabilitiesSection,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            admin.isSuperAdmin
                ? l.adminAdminsCapabilitiesHintSuper
                : l.adminAdminsCapabilitiesHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          AppSpacing.gapMd,
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              // 2 cols por defecto, 3 si hay ancho de sobra.
              final cols = w >= 700 ? 3 : (w >= 380 ? 2 : 1);
              const gap = AppSpacing.sm;
              final cellW = (w - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final cap in AdminCapability.all)
                    SizedBox(
                      width: cellW,
                      child: _CapabilityTile(
                        admin: admin,
                        capability: cap,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Toggle individual de una capability. Wrapper que delega en el
/// datasource y refresca la lista al terminar.
class _CapabilityTile extends ConsumerStatefulWidget {
  const _CapabilityTile({
    required this.admin,
    required this.capability,
  });

  final AdminRow admin;
  final String capability;

  @override
  ConsumerState<_CapabilityTile> createState() => _CapabilityTileState();
}

class _CapabilityTileState extends ConsumerState<_CapabilityTile> {
  bool _busy = false;

  Future<void> _onToggle(bool newValue) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capturamos refs derivados de context antes del await -- los
    // necesitamos en los catch sin tocar context post-await.
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final ds = ref.read(adminAclDataSourceProvider);
    try {
      if (newValue) {
        await ds.grantCapability(
          userId: widget.admin.userId,
          capability: widget.capability,
        );
      } else {
        await ds.revokeCapability(
          userId: widget.admin.userId,
          capability: widget.capability,
        );
      }
      // Invalidamos la lista entera para que se re-pinten todos los
      // toggles -- mas simple que mutar local state y se mantiene en
      // sync con el server.
      ref.invalidate(adminsListProvider);
    } on AdminAclException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: errorColor,
            content: Text(_localizeError(l, e.code)),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: errorColor,
            content: Text(l.adminAdminsPromoteUnknownError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final isOn = widget.admin.capabilities.contains(widget.capability);
    // Super tiene todas, pero las muestra como no-toggleable (locked).
    final locked = widget.admin.isSuperAdmin;

    return Tooltip(
      message: locked ? l.adminAdminsCapabilityLockedTooltip : '',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: AppRadii.brSm,
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _capabilityIcon(widget.capability),
              size: 16,
              color: isOn ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                _capabilityLabel(l, widget.capability),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: isOn,
                onChanged: (locked || _busy) ? null : _onToggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _onRevoke(
  BuildContext context,
  WidgetRef ref,
  AdminRow admin,
) async {
  final l = context.l10n;
  final ok = await AppConfirmDialog.show(
    context,
    title: l.adminAdminsRevokeConfirmTitle,
    body: l.adminAdminsRevokeConfirmBody(admin.bestDisplayName),
    confirmLabel: l.adminAdminsRevokeCta,
    danger: true,
  );
  if (ok != true) return;
  if (!context.mounted) return;
  // Capturamos refs derivados del context ANTES de cualquier await
  // adicional para evitar use_build_context_synchronously en los
  // catch blocks abajo.
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  final ds = ref.read(adminAclDataSourceProvider);
  try {
    await ds.revokeAdmin(admin.userId);
    ref.invalidate(adminsListProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.adminAdminsRevokeSuccess(admin.bestDisplayName)),
      ),
    );
  } on AdminAclException catch (e) {
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: errorColor,
        content: Text(_localizeError(l, e.code)),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: errorColor,
        content: Text(l.adminAdminsPromoteUnknownError),
      ),
    );
  }
}

/// Mapeo capability -> icono (visual cue). Sincronizado con la lista
/// de la migracion 0044 + dart `AdminCapability.all`.
IconData _capabilityIcon(String cap) {
  switch (cap) {
    case AdminCapability.manageUsers:
      return Icons.people_alt_outlined;
    case AdminCapability.managePlans:
      return Icons.sell_outlined;
    case AdminCapability.manageCoupons:
      return Icons.local_offer_outlined;
    case AdminCapability.manageBranding:
      return Icons.palette_outlined;
    case AdminCapability.manageAppBranding:
      return Icons.brush_outlined;
    case AdminCapability.manageBroadcasts:
      return Icons.campaign_outlined;
    case AdminCapability.manageChangelog:
      return Icons.article_outlined;
    case AdminCapability.manageFlags:
      return Icons.toggle_on_outlined;
    case AdminCapability.manageIncidents:
      return Icons.health_and_safety_outlined;
    case AdminCapability.viewEmailLog:
      return Icons.mark_email_read_outlined;
    case AdminCapability.viewMetrics:
      return Icons.insights_outlined;
    case AdminCapability.manageTrash:
      return Icons.delete_outline_rounded;
    case AdminCapability.runAudits:
      return Icons.shield_outlined;
    default:
      return Icons.help_outline;
  }
}

/// Mapeo capability -> label i18n.
String _capabilityLabel(AppLocalizations l, String cap) {
  switch (cap) {
    case AdminCapability.manageUsers:
      return l.adminCapManageUsers;
    case AdminCapability.managePlans:
      return l.adminCapManagePlans;
    case AdminCapability.manageCoupons:
      return l.adminCapManageCoupons;
    case AdminCapability.manageBranding:
      return l.adminCapManageBranding;
    case AdminCapability.manageAppBranding:
      return l.adminCapManageAppBranding;
    case AdminCapability.manageBroadcasts:
      return l.adminCapManageBroadcasts;
    case AdminCapability.manageChangelog:
      return l.adminCapManageChangelog;
    case AdminCapability.manageFlags:
      return l.adminCapManageFlags;
    case AdminCapability.manageIncidents:
      return l.adminCapManageIncidents;
    case AdminCapability.viewEmailLog:
      return l.adminCapViewEmailLog;
    case AdminCapability.viewMetrics:
      return l.adminCapViewMetrics;
    case AdminCapability.manageTrash:
      return l.adminCapManageTrash;
    case AdminCapability.runAudits:
      return l.adminCapRunAudits;
    default:
      return cap;
  }
}
