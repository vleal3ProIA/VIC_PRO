// ============================================================================
// subjects · /mis-temarios — "Mi Material"
// ----------------------------------------------------------------------------
// Listado limpio con filtros de TODOS los temarios del usuario actual. Reusa
// `subjectsListProvider` (que ya filtra por owner via RLS). Al pulsar una card
// se navega a /home?subjectId=X para abrir el detalle existente.
//
// Filtros:
//   * Idioma            (Wrap de FilterChips, generados desde la lista real).
//   * Estado del indice (none / generating / ready / validated).
//   * Busqueda titulo   (TextField con debounce 300ms).
//   * Orden             (mas reciente / mas antiguo / titulo A-Z).
//
// Layout: grid responsive 1/2/3 columnas. Empty state si no hay temarios.
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
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/subjects_providers.dart';
import '../../domain/subject.dart';

enum _SortMode { newestFirst, oldestFirst, titleAsc }

enum _StatusFilter { all, none, generated, validated, failed }

class MyMaterialPage extends ConsumerStatefulWidget {
  const MyMaterialPage({super.key});

  @override
  ConsumerState<MyMaterialPage> createState() => _MyMaterialPageState();
}

class _MyMaterialPageState extends ConsumerState<MyMaterialPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _search = '';
  String? _language; // null = todas.
  _StatusFilter _status = _StatusFilter.all;
  _SortMode _sort = _SortMode.newestFirst;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _search = v.trim().toLowerCase());
    });
  }

  bool _matchesStatus(Subject s) {
    switch (_status) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.none:
        return s.indexStatus == IndexStatus.none && !s.indexLocked;
      case _StatusFilter.generated:
        return s.indexStatus == IndexStatus.ready && !s.indexLocked;
      case _StatusFilter.validated:
        return s.indexLocked;
      case _StatusFilter.failed:
        return s.indexStatus == IndexStatus.failed;
    }
  }

  List<Subject> _applyFilters(List<Subject> all) {
    Iterable<Subject> it = all;
    if (_search.isNotEmpty) {
      it = it.where((s) => s.title.toLowerCase().contains(_search));
    }
    if (_language != null) {
      it = it.where((s) => s.language == _language);
    }
    it = it.where(_matchesStatus);
    final list = it.toList();
    switch (_sort) {
      case _SortMode.newestFirst:
        list.sort((a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),);
      case _SortMode.oldestFirst:
        list.sort((a, b) =>
            (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)),);
      case _SortMode.titleAsc:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(subjectsListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.home),
        ),
        title: Text(l.myMaterialTitle),
        actions: [
          TextButton.icon(
            onPressed: () => context.goNamed(RouteNames.home),
            icon: const Icon(Icons.dashboard_outlined, size: 18),
            label: Text(l.myMaterialBackToPanel),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: AppLoadingState()),
        error: (e, _) => Center(
          child: AppErrorState(
            message: l.errorGeneric,
            onRetry: () => ref.invalidate(subjectsListProvider),
            retryLabel: l.actionRetry,
          ),
        ),
        data: (subjects) {
          if (subjects.isEmpty) {
            return Center(
              child: AppEmptyState(
                icon: Icons.menu_book_outlined,
                title: l.myMaterialEmptyTitle,
                message: l.myMaterialEmptyBody,
                action: FilledButton.icon(
                  onPressed: () => context.goNamed(RouteNames.home),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l.myMaterialEmptyCta),
                ),
              ),
            );
          }
          final filtered = _applyFilters(subjects);
          final languages = subjects
              .map((s) => s.language)
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      title: l.myMaterialTitle,
                      subtitle: l.myMaterialSubtitle(subjects.length),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: _FiltersBar(
                        searchCtrl: _searchCtrl,
                        onSearchChanged: _onSearchChanged,
                        languages: languages,
                        language: _language,
                        onLanguageChanged: (v) => setState(() => _language = v),
                        status: _status,
                        onStatusChanged: (v) => setState(() => _status = v),
                        sort: _sort,
                        onSortChanged: (v) => setState(() => _sort = v),
                      ),
                    ),
                    AppSpacing.gapMd,
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: filtered.isEmpty
                          ? AppEmptyState(
                              icon: Icons.filter_alt_off_outlined,
                              title: l.myMaterialNoMatchesTitle,
                              message: l.myMaterialNoMatchesBody,
                            )
                          : _SubjectsGrid(subjects: filtered),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.languages,
    required this.language,
    required this.onLanguageChanged,
    required this.status,
    required this.onStatusChanged,
    required this.sort,
    required this.onSortChanged,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final List<String> languages;
  final String? language;
  final ValueChanged<String?> onLanguageChanged;
  final _StatusFilter status;
  final ValueChanged<_StatusFilter> onStatusChanged;
  final _SortMode sort;
  final ValueChanged<_SortMode> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchCtrl,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    hintText: l.myMaterialFilterSearch,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              DropdownButtonHideUnderline(
                child: DropdownButton<_SortMode>(
                  value: sort,
                  borderRadius: BorderRadius.circular(10),
                  items: [
                    DropdownMenuItem(
                      value: _SortMode.newestFirst,
                      child: Text(l.myMaterialSortNewest),
                    ),
                    DropdownMenuItem(
                      value: _SortMode.oldestFirst,
                      child: Text(l.myMaterialSortOldest),
                    ),
                    DropdownMenuItem(
                      value: _SortMode.titleAsc,
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
          AppSpacing.gapSm,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _StatusFilter.values)
                FilterChip(
                  label: Text(_statusLabel(context, s)),
                  selected: status == s,
                  onSelected: (_) => onStatusChanged(s),
                ),
            ],
          ),
          if (languages.isNotEmpty) ...[
            AppSpacing.gapSm,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l.myMaterialFilterAllLanguages),
                  selected: language == null,
                  onSelected: (_) => onLanguageChanged(null),
                ),
                for (final lang in languages)
                  ChoiceChip(
                    label: Text(_languageLabel(lang)),
                    selected: language == lang,
                    onSelected: (_) => onLanguageChanged(lang),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(BuildContext context, _StatusFilter s) {
    final l = context.l10n;
    switch (s) {
      case _StatusFilter.all:
        return l.myMaterialStatusAll;
      case _StatusFilter.none:
        return l.myMaterialStatusNone;
      case _StatusFilter.generated:
        return l.myMaterialStatusGenerated;
      case _StatusFilter.validated:
        return l.myMaterialStatusValidated;
      case _StatusFilter.failed:
        return l.myMaterialStatusFailed;
    }
  }
}

class _SubjectsGrid extends StatelessWidget {
  const _SubjectsGrid({required this.subjects});

  final List<Subject> subjects;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 900 ? 3 : (w >= 600 ? 2 : 1);
        const gap = AppSpacing.md;
        final cardWidth = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in subjects)
              SizedBox(
                width: cardWidth,
                child: _SubjectCard(subject: s),
              ),
          ],
        );
      },
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final lang = subject.language;
    return PremiumCard(
      // Drill-down: ya NO redirigimos al StudyPanel completo (/home).
      // El user pidio un flujo paralelo de acceso rapido: tap aqui ->
      // dashboard del temario con contadores por tipo de contenido, y
      // desde ahi a la lista/runner concreta. El StudyPanel sigue
      // existiendo intacto en /home para quien quiera la vista completa.
      onTap: () => context.goNamed(
        RouteNames.myMaterialSubject,
        pathParameters: {'id': subject.id},
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined,
                  color: scheme.primary, size: 22,),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  subject.title.isEmpty ? l.myMaterialUntitled : subject.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.gapSm,
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatusBadge(subject: subject),
              if (lang != null && lang.isNotEmpty)
                _MetaChip(
                  icon: Icons.language,
                  label: _languageLabel(lang),
                ),
            ],
          ),
          AppSpacing.gapSm,
          Text(
            _formatCreated(context, subject.createdAt),
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final Color color;
    final String label;
    final IconData icon;
    if (subject.indexLocked) {
      color = const Color(0xFF10B981); // emerald
      label = l.myMaterialStatusValidated;
      icon = Icons.verified_outlined;
    } else if (subject.indexStatus == IndexStatus.ready) {
      color = const Color(0xFF3B82F6); // blue
      label = l.myMaterialStatusGenerated;
      icon = Icons.list_alt_outlined;
    } else if (subject.indexStatus == IndexStatus.generating) {
      color = const Color(0xFFF59E0B); // amber
      label = l.myMaterialStatusGenerating;
      icon = Icons.hourglass_bottom;
    } else if (subject.indexStatus == IndexStatus.failed) {
      color = scheme.error;
      label = l.myMaterialStatusFailed;
      icon = Icons.error_outline;
    } else {
      color = scheme.onSurfaceVariant;
      label = l.myMaterialStatusNone;
      icon = Icons.edit_note;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCreated(BuildContext context, DateTime? dt) {
  final l = context.l10n;
  if (dt == null) return '';
  final f = DateFormat.yMMMd(Localizations.localeOf(context).toString());
  return l.myMaterialCreatedAt(f.format(dt.toLocal()));
}

String _languageLabel(String code) {
  switch (code.toLowerCase()) {
    case 'es':
      return 'ES';
    case 'en':
      return 'EN';
    case 'de':
      return 'DE';
    case 'fr':
      return 'FR';
    case 'it':
      return 'IT';
    case 'pt':
      return 'PT';
    case 'ru':
      return 'RU';
    case 'uk':
      return 'UK';
    default:
      return code.toUpperCase();
  }
}
