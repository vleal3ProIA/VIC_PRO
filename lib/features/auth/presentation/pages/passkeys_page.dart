import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_pagination_bar.dart';
import 'package:myapp/features/auth/application/passkey_notifier.dart';
import 'package:myapp/features/auth/application/webauthn_providers.dart';
import 'package:myapp/features/auth/domain/entities/passkey_credential.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

/// Página `/passkeys` — gestiona los passkeys del usuario:
/// listar los registrados, añadir uno nuevo, borrar.
class PasskeysPage extends ConsumerWidget {
  const PasskeysPage({super.key});

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
        title: Text(l.passkeysTitle),
      ),
      body: const PasskeysView(),
    );
  }
}

/// Cuerpo de la gestión de passkeys (sin Scaffold). Reutilizable como página
/// completa o embebido en el master-detail de Ajustes → Seguridad.
class PasskeysView extends ConsumerStatefulWidget {
  const PasskeysView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Ajustes):
  /// usa `shrinkWrap` para no requerir altura/scroll propios.
  final bool embedded;

  @override
  ConsumerState<PasskeysView> createState() => _PasskeysViewState();
}

class _PasskeysViewState extends ConsumerState<PasskeysView> {
  int _page = 0;
  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final passkeysAsync = ref.watch(myPasskeysProvider);
    final action = ref.watch(passkeyNotifierProvider);
    final notifier = ref.read(passkeyNotifierProvider.notifier);

    // Snackbar de feedback sobre la última acción.
    ref.listen<PasskeyActionState>(passkeyNotifierProvider, (prev, next) {
      if (prev?.status != PasskeyActionStatus.success &&
          next.status == PasskeyActionStatus.success) {
        context.showSnack(l.passkeyActionSuccess);
      }
      if (prev?.status != PasskeyActionStatus.failure &&
          next.status == PasskeyActionStatus.failure) {
        context.showSnack(l.passkeyActionFailure, isError: true);
      }
    });

    Future<void> onAdd() async {
      final name = await _askFriendlyName(context, l);
      if (name == null) return; // cancelado
      await notifier.register(friendlyName: name.isEmpty ? null : name);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shrinkWrap: widget.embedded,
          physics:
              widget.embedded ? const NeverScrollableScrollPhysics() : null,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.fingerprint,
                          color: context.colors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l.passkeysExplainTitle,
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.passkeysExplainBody,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: action.isBusy ? null : onAdd,
                      icon: action.isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Icon(Icons.add),
                      label: Text(l.passkeysAdd),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            passkeysAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, __) => Text(l.authErrorUnknown),
              data: (items) {
                if (items.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          l.passkeysEmpty,
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final totalPages = (items.length / _pageSize).ceil();
                final page = _page.clamp(0, totalPages - 1);
                final start = page * _pageSize;
                final end = (start + _pageSize) > items.length
                    ? items.length
                    : start + _pageSize;
                final pageItems = items.sublist(start, end);
                return Column(
                  children: [
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < pageItems.length; i++) ...[
                            _PasskeyTile(
                              passkey: pageItems[i],
                              busy: action.isBusy,
                              onDelete: () => _confirmDelete(
                                context,
                                l,
                                () => notifier.delete(pageItems[i].id),
                              ),
                            ),
                            if (i < pageItems.length - 1)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                    AppPaginationBar(
                      currentPage: page,
                      totalPages: totalPages,
                      onPrevious: () => setState(() => _page = page - 1),
                      onNext: () => setState(() => _page = page + 1),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askFriendlyName(
    BuildContext context,
    AppLocalizations l,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.passkeysAddDialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l.passkeysAddDialogLabel,
            hintText: l.passkeysAddDialogHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l.actionContinue),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppLocalizations l,
    Future<void> Function() doDelete,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.passkeysDeleteConfirmTitle),
        content: Text(l.passkeysDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.passkeysDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await doDelete();
  }
}

class _PasskeyTile extends StatelessWidget {
  const _PasskeyTile({
    required this.passkey,
    required this.busy,
    required this.onDelete,
  });

  final PasskeyCredential passkey;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final created = DateFormat.yMMMd(localeCode).format(passkey.createdAt);

    return ListTile(
      leading: const Icon(Icons.key_outlined),
      title: Text(
        (passkey.friendlyName?.isNotEmpty ?? false)
            ? passkey.friendlyName!
            : l.passkeysUnnamed,
      ),
      subtitle: Text(l.passkeysCreatedOn(created)),
      trailing: IconButton(
        tooltip: l.passkeysDelete,
        icon: Icon(Icons.delete_outline, color: context.colors.error),
        onPressed: busy ? null : onDelete,
      ),
    );
  }
}
