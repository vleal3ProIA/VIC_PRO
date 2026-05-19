import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/changelog_providers.dart';
import '../../domain/changelog_entry.dart';
import '../widgets/changelog_category_visuals.dart';
import '../widgets/changelog_editor_dialog.dart';

/// `/admin/changelog` — CRUD de entradas de changelog. Admin-only
/// (protegido por el router). Lista borradores y publicadas; permite
/// crear, editar, publicar/despublicar y borrar.
class AdminChangelogPage extends ConsumerWidget {
  const AdminChangelogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(changelogEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.admin),
        ),
        title: Text(l.adminChangelogTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(changelogEntriesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.adminChangelogCreate),
        onPressed: () => _onCreate(context, ref),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
          child: async.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.adminChangelogLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(changelogEntriesProvider),
              retryLabel: l.actionRetry,
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return AppEmptyState(
                  icon: Icons.campaign_outlined,
                  title: l.adminChangelogEmptyTitle,
                  message: l.adminChangelogEmptyBody,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  96,
                ),
                itemCount: entries.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _EntryTile(entry: entries[i]),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onCreate(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final created = await showDialog<ChangelogEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ChangelogEditorDialog(),
    );
    if (created == null || !context.mounted) return;
    ref.invalidate(changelogEntriesProvider);
    context.showSnack(l.adminChangelogCreated);
  }
}

class _EntryTile extends ConsumerStatefulWidget {
  const _EntryTile({required this.entry});
  final ChangelogEntry entry;

  @override
  ConsumerState<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends ConsumerState<_EntryTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode);
    final e = widget.entry;
    final visuals = visualsFor(context, e.category);

    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + 4,
        AppSpacing.sm,
        AppSpacing.sm + 4,
      ),
      child: Row(
        children: [
          Icon(visuals.icon, color: visuals.color),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        style: context.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (e.isDraft)
                      PremiumBadge(
                        label: l.adminChangelogStatusDraft,
                        variant: PremiumBadgeVariant.neutral,
                        dense: true,
                      )
                    else
                      PremiumBadge(
                        label: l.adminChangelogStatusPublished,
                        variant: PremiumBadgeVariant.info,
                        dense: true,
                      ),
                  ],
                ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      if (e.version != null)
                        Text(
                          e.version!,
                          style: context.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        visuals.label(l),
                        style: context.textTheme.bodySmall?.copyWith(
                          color: visuals.color,
                        ),
                      ),
                      if (e.publishedAt != null)
                        Text(
                          l.adminChangelogPublishedAt(
                            fmt.format(e.publishedAt!.toLocal()),
                          ),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        )
                      else
                        Text(
                          l.adminChangelogDraftSince(
                            fmt.format(e.createdAt.toLocal()),
                          ),
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
              tooltip: l.adminChangelogActions,
              onSelected: (v) async {
                switch (v) {
                  case 'edit':
                    await _onEdit();
                  case 'toggle':
                    await _onTogglePublish();
                  case 'delete':
                    await _onDelete();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(l.adminChangelogEdit),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Row(
                    children: [
                      Icon(
                        e.isDraft
                            ? Icons.publish_outlined
                            : Icons.unpublished_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        e.isDraft
                            ? l.adminChangelogPublish
                            : l.adminChangelogUnpublish,
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: context.colors.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l.adminChangelogDelete,
                        style: TextStyle(color: context.colors.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
      ),
    );
  }

  Future<void> _onEdit() async {
    final l = context.l10n;
    final updated = await showDialog<ChangelogEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangelogEditorDialog(initial: widget.entry),
    );
    if (updated == null || !mounted) return;
    ref.invalidate(changelogEntriesProvider);
    context.showSnack(l.adminChangelogUpdated);
  }

  Future<void> _onTogglePublish() async {
    final l = context.l10n;
    final e = widget.entry;
    setState(() => _busy = true);
    try {
      await ref.read(changelogDataSourceProvider).update(
            id: e.id,
            title: e.title,
            body: e.body,
            category: e.category,
            version: e.version,
            publishedAt: e.isDraft ? DateTime.now() : null,
          );
      if (!mounted) return;
      ref.invalidate(changelogEntriesProvider);
      context.showSnack(
        e.isDraft ? l.adminChangelogPublished : l.adminChangelogUnpublished,
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.adminChangelogUpdateError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onDelete() async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.adminChangelogDeleteConfirmTitle,
      body: l.adminChangelogDeleteConfirmBody(widget.entry.title),
      confirmLabel: l.adminChangelogDelete,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(changelogDataSourceProvider).delete(widget.entry.id);
      if (!mounted) return;
      ref.invalidate(changelogEntriesProvider);
      context.showSnack(l.adminChangelogDeleted);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.adminChangelogDeleteError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
