import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../application/admin_trash_providers.dart';
import '../../domain/deleted_tenant.dart';

/// `/admin/trash` — papelera de tenants soft-borrados.
///
/// El admin global ve todos los tenants con `deleted_at != null` y puede
/// restaurarlos en 1 click. Cuando restauras, el tenant y todos sus
/// miembros vuelven a la vida en bloque (la RPC hace el cascade).
///
/// Solo accesible bajo guard admin del router.
class AdminTrashPage extends ConsumerWidget {
  const AdminTrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(deletedTenantsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.admin),
        ),
        title: Text(l.adminTrashTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(deletedTenantsProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: async.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.adminTrashLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(deletedTenantsProvider),
              retryLabel: l.actionRetry,
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return AppEmptyState(
                  icon: Icons.delete_outline,
                  message: l.adminTrashEmpty,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _DeletedTenantCard(tenant: rows[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DeletedTenantCard extends ConsumerStatefulWidget {
  const _DeletedTenantCard({required this.tenant});
  final DeletedTenant tenant;

  @override
  ConsumerState<_DeletedTenantCard> createState() => _DeletedTenantCardState();
}

class _DeletedTenantCardState extends ConsumerState<_DeletedTenantCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final formattedDate = DateFormat.yMMMMd(localeCode)
        .add_Hm()
        .format(widget.tenant.deletedAt.toLocal());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.tenant.name,
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.lineThrough,
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.tenant.slug,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.adminTrashDeletedAt(formattedDate),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    l.adminTrashMemberCount(widget.tenant.memberCount),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.restore_outlined),
              label: Text(l.adminTrashRestore),
              onPressed: _busy ? null : _onRestore,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onRestore() async {
    final l = context.l10n;
    final confirm = await AppConfirmDialog.show(
      context,
      title: l.adminTrashRestoreConfirmTitle,
      body: l.adminTrashRestoreConfirmBody(widget.tenant.name),
      confirmLabel: l.adminTrashRestore,
      cancelLabel: l.actionCancel,
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminTrashDataSourceProvider)
          .restoreTenant(widget.tenant.id);
      if (!mounted) return;
      ref.invalidate(deletedTenantsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminTrashRestored(widget.tenant.name))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminTrashRestoreError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
