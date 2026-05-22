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
import 'package:myapp/core/widgets/app_pagination_bar.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/incidents_providers.dart';
import '../../domain/incident.dart';
import '../incident_visuals.dart';
import '../widgets/incident_editor_dialog.dart';

/// `/admin/incidents` — CRUD de incidentes. Admin-only via router
/// guard + RLS. Borradores y publicados; permite editar, publicar,
/// cambiar status y borrar.
class AdminIncidentsPage extends ConsumerWidget {
  const AdminIncidentsPage({super.key});

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
        title: Text(l.adminIncidentsTitle),
      ),
      body: const AdminIncidentsView(),
    );
  }
}

/// Cuerpo del CRUD de incidentes (sin Scaffold). Reutilizable como página
/// completa o embebido en el master-detail de Administración.
///
/// El botón de crear (antes un FAB del Scaffold) se reposiciona dentro del
/// panel para que funcione igual embebido y a pantalla completa.
class AdminIncidentsView extends ConsumerStatefulWidget {
  const AdminIncidentsView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Admin).
  final bool embedded;

  @override
  ConsumerState<AdminIncidentsView> createState() => _AdminIncidentsViewState();
}

class _AdminIncidentsViewState extends ConsumerState<AdminIncidentsView> {
  int _page = 0;
  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(adminIncidentsProvider);

    final content = async.when(
      loading: () => const AppLoadingState(),
      error: (e, _) => AppErrorState(
        message: l.adminIncidentsLoadError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(adminIncidentsProvider),
        retryLabel: l.actionRetry,
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return AppEmptyState(
            icon: Icons.health_and_safety_outlined,
            title: l.adminIncidentsEmptyTitle,
            message: l.adminIncidentsEmptyBody,
          );
        }
        final totalPages = (entries.length / _pageSize).ceil();
        final page = _page.clamp(0, totalPages - 1);
        final start = page * _pageSize;
        final end = (start + _pageSize) > entries.length
            ? entries.length
            : start + _pageSize;
        final pageEntries = entries.sublist(start, end);
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
          itemCount: pageEntries.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) => _IncidentTile(incident: pageEntries[i]),
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
                    onPressed: () => ref.invalidate(adminIncidentsProvider),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: _onCreate,
                    icon: const Icon(Icons.add),
                    label: Text(l.adminIncidentsCreate),
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

  Future<void> _onCreate() async {
    final l = context.l10n;
    final created = await showDialog<Incident>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const IncidentEditorDialog(),
    );
    if (created == null || !mounted) return;
    ref
      ..invalidate(adminIncidentsProvider)
      ..invalidate(activeIncidentsProvider)
      ..invalidate(incidentsHistoryProvider);
    context.showSnack(l.adminIncidentsCreated);
  }
}

class _IncidentTile extends ConsumerStatefulWidget {
  const _IncidentTile({required this.incident});
  final Incident incident;

  @override
  ConsumerState<_IncidentTile> createState() => _IncidentTileState();
}

class _IncidentTileState extends ConsumerState<_IncidentTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();
    final i = widget.incident;
    final sevV = incidentSeverityVisuals(context, i.severity);
    final statusV = incidentStatusVisuals(context, i.status);

    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + 4,
        AppSpacing.sm,
        AppSpacing.sm + 4,
      ),
      child: Row(
        children: [
          Icon(sevV.icon, color: sevV.color),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        i.title,
                        style: context.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!i.published)
                      PremiumBadge(
                        label: l.adminIncidentsStatusDraft,
                        variant: PremiumBadgeVariant.neutral,
                        dense: true,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      sevV.label(l),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: sevV.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '·',
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      statusV.label(l),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: statusV.color,
                      ),
                    ),
                    Text(
                      '·',
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      fmt.format(i.startedAt.toLocal()),
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
            tooltip: l.adminIncidentsActions,
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  await _onEdit();
                case 'togglePublish':
                  await _onTogglePublish();
                case 'resolve':
                  await _onResolve();
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
                    Text(l.adminIncidentsEdit),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'togglePublish',
                child: Row(
                  children: [
                    Icon(
                      i.published
                          ? Icons.unpublished_outlined
                          : Icons.publish_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      i.published
                          ? l.adminIncidentsUnpublish
                          : l.adminIncidentsPublish,
                    ),
                  ],
                ),
              ),
              if (i.isActive)
                PopupMenuItem(
                  value: 'resolve',
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 18),
                      const SizedBox(width: 8),
                      Text(l.adminIncidentsResolve),
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
                      l.adminIncidentsDelete,
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
    final updated = await showDialog<Incident>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncidentEditorDialog(initial: widget.incident),
    );
    if (updated == null || !mounted) return;
    _invalidateAll();
    context.showSnack(l.adminIncidentsUpdated);
  }

  Future<void> _onTogglePublish() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final i = widget.incident;
      await ref.read(incidentsDataSourceProvider).update(
            id: i.id,
            title: i.title,
            body: i.body,
            status: i.status,
            severity: i.severity,
            components: i.components,
            startedAt: i.startedAt,
            published: !i.published,
          );
      if (!mounted) return;
      _invalidateAll();
      context.showSnack(
        i.published ? l.adminIncidentsUnpublished : l.adminIncidentsPublished,
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.adminIncidentsUpdateError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onResolve() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final i = widget.incident;
      await ref.read(incidentsDataSourceProvider).update(
            id: i.id,
            title: i.title,
            body: i.body,
            status: IncidentStatus.resolved,
            severity: i.severity,
            components: i.components,
            startedAt: i.startedAt,
            published: i.published,
          );
      if (!mounted) return;
      _invalidateAll();
      context.showSnack(l.adminIncidentsResolved);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.adminIncidentsUpdateError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onDelete() async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.adminIncidentsDeleteConfirmTitle,
      body: l.adminIncidentsDeleteConfirmBody(widget.incident.title),
      confirmLabel: l.adminIncidentsDelete,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(incidentsDataSourceProvider).delete(widget.incident.id);
      if (!mounted) return;
      _invalidateAll();
      context.showSnack(l.adminIncidentsDeleted);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.adminIncidentsDeleteError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidateAll() {
    ref
      ..invalidate(adminIncidentsProvider)
      ..invalidate(activeIncidentsProvider)
      ..invalidate(incidentsHistoryProvider);
  }
}
