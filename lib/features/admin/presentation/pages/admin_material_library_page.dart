// ============================================================================
// admin · /admin/material-library — Biblioteca de material
// ----------------------------------------------------------------------------
// SOLO super-admin. Lista TODOS los temarios del proyecto (saltando RLS por
// owner via RPC SECURITY DEFINER `admin_list_subjects`, ver migracion 0078).
// Tabla densa con filtros (owner / idioma / estado / busqueda titulo / fechas)
// y paginacion 50 por pagina. Vista solo lectura.
//
// Al pulsar una fila → `/admin/material-library/:id` (read-only de las vistas
// del subject: indice, contenidos generados, V/F, ensayos, flashcards, notas).
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_pagination_bar.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/features/subjects/application/subjects_providers.dart';
import 'package:myapp/features/subjects/domain/subject.dart';

class AdminMaterialLibraryPage extends ConsumerWidget {
  const AdminMaterialLibraryPage({super.key});

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
        title: Text(l.adminMaterialLibraryTitle),
      ),
      body: const _AdminMaterialLibraryView(),
    );
  }
}

class _AdminMaterialLibraryView extends ConsumerStatefulWidget {
  const _AdminMaterialLibraryView();

  @override
  ConsumerState<_AdminMaterialLibraryView> createState() =>
      _AdminMaterialLibraryViewState();
}

class _AdminMaterialLibraryViewState
    extends ConsumerState<_AdminMaterialLibraryView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _ownerSearchCtrl = TextEditingController();
  Timer? _debounce;
  String _ownerLabel = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _ownerSearchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _updateQuery(AdminSubjectsQuery Function(AdminSubjectsQuery) f) {
    final notifier = ref.read(adminSubjectsQueryProvider.notifier);
    notifier.update(f);
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _updateQuery((q) => q.copyWith(
            titleSearch: v.trim().isEmpty ? null : v.trim(),
            offset: 0,
          ),);
    });
  }

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final current = from
        ? ref.read(adminSubjectsQueryProvider).fromDate
        : ref.read(adminSubjectsQueryProvider).toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (!mounted) return;
    if (picked == null) return;
    _updateQuery((q) => from
        ? q.copyWith(fromDate: picked, offset: 0)
        : q.copyWith(toDate: picked, offset: 0),);
  }

  Future<void> _pickOwner() async {
    final result = await showDialog<AdminOwnerRow?>(
      context: context,
      builder: (_) =>
          _OwnerPickerDialog(initialSearch: _ownerSearchCtrl.text),
    );
    if (!mounted) return;
    if (result == null) return;
    setState(() => _ownerLabel = result.label);
    _updateQuery((q) => q.copyWith(ownerUserId: result.userId, offset: 0));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final query = ref.watch(adminSubjectsQueryProvider);
    final async = ref.watch(adminSubjectsPageProvider(query));

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
                title: l.adminMaterialLibraryTitle,
                subtitle: l.adminMaterialLibrarySubtitle,
                padding: EdgeInsets.zero,
              ),
            ),
            AppSpacing.gapMd,
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _FiltersBar(
                searchCtrl: _searchCtrl,
                onSearchChanged: _onSearchChanged,
                query: query,
                onLanguageChanged: (v) =>
                    _updateQuery((q) => q.copyWith(language: v, offset: 0)),
                onStatusChanged: (v) => _updateQuery(
                  (q) => q.copyWith(indexStatus: v, offset: 0),
                ),
                onSortChanged: (v) => _updateQuery((q) => q.copyWith(sortBy: v)),
                ownerLabel: _ownerLabel,
                onPickOwner: _pickOwner,
                onClearOwner: () {
                  setState(() => _ownerLabel = '');
                  _updateQuery((q) => q.copyWith(ownerUserId: null, offset: 0));
                },
                onPickFromDate: () => _pickDate(from: true),
                onPickToDate: () => _pickDate(from: false),
                onClearDates: () => _updateQuery((q) => q.copyWith(
                      fromDate: null,
                      toDate: null,
                      offset: 0,
                    ),),
                onOnlyPublicDomainChanged: (v) => _updateQuery(
                  (q) => q.copyWith(onlyPublicDomain: v, offset: 0),
                ),
              ),
            ),
            AppSpacing.gapMd,
            Expanded(
              child: async.when(
                loading: () => const Center(child: AppLoadingState()),
                error: (e, _) => Center(
                  child: AppErrorState(
                    message: l.adminMaterialLibraryLoadError,
                    detail: e.toString(),
                    onRetry: () =>
                        ref.invalidate(adminSubjectsPageProvider(query)),
                    retryLabel: l.actionRetry,
                  ),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return Center(
                      child: AppEmptyState(
                        icon: Icons.library_books_outlined,
                        title: l.adminMaterialLibraryEmptyTitle,
                        message: l.adminMaterialLibraryEmptyBody,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding:
                              const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                          child: _SubjectsTable(rows: rows),
                        ),
                      ),
                      AppPaginationBar(
                        currentPage: query.offset ~/ query.limit,
                        // No tenemos total_count del backend (solo la pagina).
                        // Si la pagina viene llena, asumimos que puede haber
                        // mas; en cuanto venga incompleta nos quedamos aqui.
                        totalPages: rows.length < query.limit
                            ? (query.offset ~/ query.limit) + 1
                            : (query.offset ~/ query.limit) + 2,
                        onPrevious: () => _updateQuery((q) => q.copyWith(
                              offset: (q.offset - q.limit).clamp(0, 1 << 30),
                            ),),
                        onNext: () => _updateQuery((q) =>
                            q.copyWith(offset: q.offset + q.limit),),
                      ),
                    ],
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

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.query,
    required this.onLanguageChanged,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.ownerLabel,
    required this.onPickOwner,
    required this.onClearOwner,
    required this.onPickFromDate,
    required this.onPickToDate,
    required this.onClearDates,
    required this.onOnlyPublicDomainChanged,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final AdminSubjectsQuery query;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<AdminSubjectsSort> onSortChanged;
  final String ownerLabel;
  final VoidCallback onPickOwner;
  final VoidCallback onClearOwner;
  final VoidCallback onPickFromDate;
  final VoidCallback onPickToDate;
  final VoidCallback onClearDates;
  final ValueChanged<bool> onOnlyPublicDomainChanged;

  static const _languages = [
    'es',
    'en',
    'de',
    'fr',
    'it',
    'pt',
    'ru',
    'uk',
  ];

  static const _statuses = ['none', 'generating', 'ready', 'failed'];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final dateFmt = DateFormat.yMMMd(localeCode);
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: searchCtrl,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                hintText: l.adminMaterialLibraryFilterSearch,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          // Owner picker.
          OutlinedButton.icon(
            onPressed: onPickOwner,
            icon: const Icon(Icons.person_search, size: 18),
            label: Text(
              ownerLabel.isEmpty
                  ? l.adminMaterialLibraryFilterOwner
                  : '${l.adminMaterialLibraryFilterOwner}: $ownerLabel',
            ),
          ),
          if (query.ownerUserId != null)
            IconButton(
              tooltip: l.adminMaterialLibraryFilterClear,
              onPressed: onClearOwner,
              icon: const Icon(Icons.close, size: 18),
            ),
          // Language dropdown.
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: query.language,
              hint: Text(l.adminMaterialLibraryFilterLanguage),
              borderRadius: BorderRadius.circular(10),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l.adminMaterialLibraryFilterAllLanguages),
                ),
                for (final lang in _languages)
                  DropdownMenuItem<String?>(
                    value: lang,
                    child: Text(lang.toUpperCase()),
                  ),
              ],
              onChanged: onLanguageChanged,
            ),
          ),
          // Status dropdown.
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: query.indexStatus,
              hint: Text(l.adminMaterialLibraryFilterStatus),
              borderRadius: BorderRadius.circular(10),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l.adminMaterialLibraryFilterAllStatuses),
                ),
                for (final s in _statuses)
                  DropdownMenuItem<String?>(
                    value: s,
                    child: Text(_statusLabel(context, s)),
                  ),
              ],
              onChanged: onStatusChanged,
            ),
          ),
          // Date range.
          OutlinedButton.icon(
            onPressed: onPickFromDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              query.fromDate == null
                  ? l.adminMaterialLibraryFilterFrom
                  : '${l.adminMaterialLibraryFilterFrom}: ${dateFmt.format(query.fromDate!)}',
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPickToDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              query.toDate == null
                  ? l.adminMaterialLibraryFilterTo
                  : '${l.adminMaterialLibraryFilterTo}: ${dateFmt.format(query.toDate!)}',
            ),
          ),
          if (query.fromDate != null || query.toDate != null)
            IconButton(
              tooltip: l.adminMaterialLibraryFilterClear,
              onPressed: onClearDates,
              icon: const Icon(Icons.close, size: 18),
            ),
          // Toggle "solo dominio publico". Util para el super que esta
          // buscando material descargable.
          FilterChip(
            label: Text(l.adminMaterialLibraryFilterOnlyPublicDomain),
            selected: query.onlyPublicDomain,
            onSelected: onOnlyPublicDomainChanged,
            avatar: const Icon(Icons.public_outlined, size: 16),
          ),
          // Sort.
          DropdownButtonHideUnderline(
            child: DropdownButton<AdminSubjectsSort>(
              value: query.sortBy,
              borderRadius: BorderRadius.circular(10),
              items: [
                DropdownMenuItem(
                  value: AdminSubjectsSort.newestFirst,
                  child: Text(l.myMaterialSortNewest),
                ),
                DropdownMenuItem(
                  value: AdminSubjectsSort.oldestFirst,
                  child: Text(l.myMaterialSortOldest),
                ),
                DropdownMenuItem(
                  value: AdminSubjectsSort.titleAsc,
                  child: Text(l.myMaterialSortTitle),
                ),
              ],
              onChanged: (v) {
                if (v != null) onSortChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(BuildContext context, String s) {
    final l = context.l10n;
    switch (s) {
      case 'none':
        return l.myMaterialStatusNone;
      case 'generating':
        return l.myMaterialStatusGenerating;
      case 'ready':
        return l.myMaterialStatusGenerated;
      case 'failed':
        return l.myMaterialStatusFailed;
      default:
        return s;
    }
  }
}

class _SubjectsTable extends StatelessWidget {
  const _SubjectsTable({required this.rows});

  final List<AdminSubjectRow> rows;

  @override
  Widget build(BuildContext context) {
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
            dataRowMaxHeight: 56,
            columnSpacing: AppSpacing.lg,
            columns: [
              DataColumn(label: Text(l.adminMaterialLibraryColTitle)),
              DataColumn(label: Text(l.adminMaterialLibraryColOwner)),
              DataColumn(label: Text(l.adminMaterialLibraryColLanguage)),
              DataColumn(
                label: Text(l.adminMaterialLibraryColDocs),
                numeric: true,
              ),
              DataColumn(
                label: Text(l.adminMaterialLibraryColNodes),
                numeric: true,
              ),
              DataColumn(label: Text(l.adminMaterialLibraryColStatus)),
              // Nueva columna: muestra el origen "libre" del material —
              // shareable (verde) o dominio publico (azul). Vacia si
              // ninguno.
              DataColumn(label: Text(l.adminMaterialLibraryColAccess)),
              DataColumn(label: Text(l.adminMaterialLibraryColCreated)),
              DataColumn(label: Text(l.adminMaterialLibraryColActions)),
            ],
            rows: [
              for (final r in rows) _row(context, r, fmt),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _row(
    BuildContext context,
    AdminSubjectRow r,
    DateFormat fmt,
  ) {
    final l = context.l10n;
    final s = r.subject;
    void open() => context.pushNamed(
          RouteNames.adminMaterialLibrarySubject,
          pathParameters: {'id': s.id},
        );
    return DataRow(
      onSelectChanged: (_) => open(),
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              s.title.isEmpty ? l.myMaterialUntitled : s.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.ownerLabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if ((r.ownerEmail ?? '').isNotEmpty)
                  Text(
                    r.ownerEmail!,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        DataCell(Text((s.language ?? '—').toUpperCase())),
        DataCell(Text('${r.docsCount}')),
        DataCell(Text('${r.nodesCount}')),
        DataCell(_StatusCell(subject: s)),
        DataCell(_AccessCell(row: r)),
        DataCell(
          Text(
            s.createdAt == null ? '—' : fmt.format(s.createdAt!.toLocal()),
          ),
        ),
        DataCell(
          IconButton(
            tooltip: l.adminMaterialLibraryViewSubject,
            icon: const Icon(Icons.visibility_outlined),
            onPressed: open,
          ),
        ),
      ],
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    Color color;
    String label;
    if (subject.indexLocked) {
      color = const Color(0xFF10B981);
      label = l.myMaterialStatusValidated;
    } else if (subject.indexStatus == IndexStatus.ready) {
      color = const Color(0xFF3B82F6);
      label = l.myMaterialStatusGenerated;
    } else if (subject.indexStatus == IndexStatus.generating) {
      color = const Color(0xFFF59E0B);
      label = l.myMaterialStatusGenerating;
    } else if (subject.indexStatus == IndexStatus.failed) {
      color = scheme.error;
      label = l.myMaterialStatusFailed;
    } else {
      color = scheme.onSurfaceVariant;
      label = l.myMaterialStatusNone;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Celda "acceso libre": muestra el origen por el que un subject es de
/// dominio publico, si lo es:
///   - shareable=true     → badge VERDE "Libre" (declarado por el owner).
///   - isPublicDomain && !shareable → badge AZUL "Dominio publico" (matched
///     por la whitelist `public_domain_sources` via source_url/file_name).
///   - ninguno            → guion (—).
class _AccessCell extends StatelessWidget {
  const _AccessCell({required this.row});
  final AdminSubjectRow row;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (row.subject.shareable) {
      return PremiumBadge(
        label: l.materialShareableBadge,
        variant: PremiumBadgeVariant.success,
        icon: Icons.bookmark_added_outlined,
        dense: true,
      );
    }
    if (row.isPublicDomain) {
      return PremiumBadge(
        label: l.materialPublicDomainBadge,
        variant: PremiumBadgeVariant.info,
        icon: Icons.public_outlined,
        dense: true,
      );
    }
    return Text(
      '—',
      style: context.textTheme.bodySmall?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    );
  }
}

/// Dialogo simple para elegir owner. Hace fetch al autocomplete con
/// debounce 300ms cada vez que el user tipea.
class _OwnerPickerDialog extends ConsumerStatefulWidget {
  const _OwnerPickerDialog({required this.initialSearch});
  final String initialSearch;

  @override
  ConsumerState<_OwnerPickerDialog> createState() => _OwnerPickerDialogState();
}

class _OwnerPickerDialogState extends ConsumerState<_OwnerPickerDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialSearch);
  String _search = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search = widget.initialSearch;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _search = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(adminSubjectOwnersProvider(_search));
    return AlertDialog(
      title: Text(l.adminMaterialLibraryFilterOwner),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: l.adminMaterialLibraryOwnerSearchHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            AppSpacing.gapSm,
            Expanded(
              child: async.when(
                loading: () => const Center(child: AppLoadingState()),
                error: (e, _) => Center(
                  child: Text(
                    e.toString(),
                    style: TextStyle(color: context.colors.error),
                  ),
                ),
                data: (owners) {
                  if (owners.isEmpty) {
                    return Center(
                      child: Text(l.adminMaterialLibraryNoOwners),
                    );
                  }
                  return ListView.separated(
                    itemCount: owners.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final o = owners[i];
                      return ListTile(
                        title: Text(o.label),
                        subtitle: Text(o.email ?? ''),
                        trailing: Text('${o.subjectsCount}'),
                        onTap: () => Navigator.pop(context, o),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.actionCancel),
        ),
      ],
    );
  }
}
