// ============================================================================
// admin · /admin/public-domain-sources — Whitelist de fuentes de dominio
//                                       publico (super-admin only)
// ----------------------------------------------------------------------------
// Permite gestionar la lista de PATTERNS que, si aparecen en el `source_url`
// (o file_name / extension) de un documento, marcan el subject como "de
// dominio publico". Esto desbloquea para el super-admin la descarga del
// documento original via la storage policy `temarios_super_read_public_domain`
// (migracion 0079).
//
// Hard rule: aunque la UI esta protegida por el router guard, la RLS de la
// tabla `public_domain_sources` exige `is_super_admin()` en INSERT/UPDATE/
// DELETE. Si alguien bypaseara la UI, el servidor rechazaria con
// permission_denied.
// ============================================================================

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

import '../../application/public_domain_sources_providers.dart';
import '../../domain/public_domain_source.dart';

class AdminPublicDomainSourcesPage extends ConsumerWidget {
  const AdminPublicDomainSourcesPage({super.key});

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
        title: Text(l.adminPublicDomainSourcesTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(publicDomainSourcesAllProvider),
          ),
        ],
      ),
      body: const _AdminPublicDomainSourcesView(),
    );
  }
}

class _AdminPublicDomainSourcesView extends ConsumerWidget {
  const _AdminPublicDomainSourcesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(publicDomainSourcesAllProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: PageHeader(
                title: l.adminPublicDomainSourcesTitle,
                subtitle: l.adminPublicDomainSourcesDescription,
                padding: EdgeInsets.zero,
                actions: [
                  PremiumButton(
                    label: l.adminPublicDomainSourcesAddNew,
                    leadingIcon: Icons.add,
                    onPressed: () => _showEditDialog(context, ref, null),
                  ),
                ],
              ),
            ),
            AppSpacing.gapMd,
            Expanded(
              child: async.when(
                loading: () => const Center(child: AppLoadingState()),
                error: (e, _) => Center(
                  child: AppErrorState(
                    message: l.adminPublicDomainSourcesLoadError,
                    detail: e.toString(),
                    onRetry: () =>
                        ref.invalidate(publicDomainSourcesAllProvider),
                    retryLabel: l.actionRetry,
                  ),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return Center(
                      child: AppEmptyState(
                        icon: Icons.public_outlined,
                        title: l.adminPublicDomainSourcesEmptyTitle,
                        message: l.adminPublicDomainSourcesEmptyBody,
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: _SourcesTable(rows: rows),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcesTable extends ConsumerWidget {
  const _SourcesTable({required this.rows});
  final List<PublicDomainSource> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode);
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadii.brCard,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 60,
            columnSpacing: AppSpacing.lg,
            columns: [
              DataColumn(label: Text(l.adminPublicDomainSourcesLabel)),
              DataColumn(label: Text(l.adminPublicDomainSourcesPattern)),
              DataColumn(label: Text(l.adminPublicDomainSourcesMatchType)),
              DataColumn(label: Text(l.adminPublicDomainSourcesEnabled)),
              DataColumn(label: Text(l.adminPublicDomainSourcesNotes)),
              DataColumn(label: Text(l.adminMaterialLibraryColCreated)),
              DataColumn(label: Text(l.adminMaterialLibraryColActions)),
            ],
            rows: [
              for (final r in rows) _row(context, ref, r, fmt),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _row(
    BuildContext context,
    WidgetRef ref,
    PublicDomainSource r,
    DateFormat fmt,
  ) {
    final l = context.l10n;
    return DataRow(
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              r.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              r.pattern,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        DataCell(Text(_matchTypeLabel(context, r.matchType))),
        DataCell(
          Switch.adaptive(
            value: r.enabled,
            onChanged: (v) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(publicDomainSourcesDataSourceProvider)
                    .setEnabled(r.id, enabled: v);
                ref.invalidate(publicDomainSourcesAllProvider);
                ref.invalidate(publicDomainSourcesEnabledProvider);
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              r.notes ?? '—',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        DataCell(
          Text(r.createdAt == null ? '—' : fmt.format(r.createdAt!.toLocal())),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l.actionEdit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showEditDialog(context, ref, r),
              ),
              IconButton(
                tooltip: l.aiDeleteCta,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref, r),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _matchTypeLabel(BuildContext context, PublicDomainMatchType t) {
  final l = context.l10n;
  switch (t) {
    case PublicDomainMatchType.domain:
      return l.adminPublicDomainSourcesMatchTypeDomain;
    case PublicDomainMatchType.filename:
      return l.adminPublicDomainSourcesMatchTypeFilename;
    case PublicDomainMatchType.extension:
      return l.adminPublicDomainSourcesMatchTypeExtension;
  }
}

Future<void> _showEditDialog(
  BuildContext context,
  WidgetRef ref,
  PublicDomainSource? existing,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _EditSourceDialog(existing: existing),
  );
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  PublicDomainSource r,
) async {
  final l = context.l10n;
  // Capturamos el messenger ANTES del primer await para no incurrir en el
  // lint use_build_context_synchronously si el widget se desmonta mientras
  // el dialog esta abierto.
  final messenger = ScaffoldMessenger.of(context);
  final ok = await AppConfirmDialog.show(
    context,
    title: l.adminPublicDomainSourcesDeleteTitle,
    body: l.adminPublicDomainSourcesDeleteBody(r.label),
    confirmLabel: l.aiDeleteCta,
    cancelLabel: l.actionCancel,
    danger: true,
  );
  if (ok != true) return;
  try {
    await ref.read(publicDomainSourcesDataSourceProvider).delete(r.id);
    ref.invalidate(publicDomainSourcesAllProvider);
    ref.invalidate(publicDomainSourcesEnabledProvider);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

class _EditSourceDialog extends ConsumerStatefulWidget {
  const _EditSourceDialog({required this.existing});
  final PublicDomainSource? existing;

  @override
  ConsumerState<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends ConsumerState<_EditSourceDialog> {
  late final TextEditingController _pattern;
  late final TextEditingController _label;
  late final TextEditingController _notes;
  late PublicDomainMatchType _matchType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pattern = TextEditingController(text: widget.existing?.pattern ?? '');
    _label = TextEditingController(text: widget.existing?.label ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
    _matchType = widget.existing?.matchType ?? PublicDomainMatchType.domain;
  }

  @override
  void dispose() {
    _pattern.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pattern = _pattern.text.trim();
    final label = _label.text.trim();
    if (pattern.length < 2 || label.isEmpty) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final ds = ref.read(publicDomainSourcesDataSourceProvider);
      if (widget.existing == null) {
        await ds.create(
          pattern: pattern,
          label: label,
          matchType: _matchType,
          notes: _notes.text.trim(),
        );
      } else {
        await ds.update(
          id: widget.existing!.id,
          pattern: pattern,
          label: label,
          matchType: _matchType,
          notes: _notes.text.trim(),
        );
      }
      ref.invalidate(publicDomainSourcesAllProvider);
      ref.invalidate(publicDomainSourcesEnabledProvider);
      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? l.adminPublicDomainSourcesAddNew
            : l.adminPublicDomainSourcesEditTitle,
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _label,
              decoration: InputDecoration(
                labelText: l.adminPublicDomainSourcesLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            AppSpacing.gapSm,
            TextField(
              controller: _pattern,
              decoration: InputDecoration(
                labelText: l.adminPublicDomainSourcesPattern,
                hintText: 'boe.es',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            AppSpacing.gapSm,
            DropdownButtonFormField<PublicDomainMatchType>(
              initialValue: _matchType,
              decoration: InputDecoration(
                labelText: l.adminPublicDomainSourcesMatchType,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: PublicDomainMatchType.values
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(_matchTypeLabel(context, t)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _matchType = v ?? _matchType),
            ),
            AppSpacing.gapSm,
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l.adminPublicDomainSourcesNotes,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l.actionSave),
        ),
      ],
    );
  }
}
