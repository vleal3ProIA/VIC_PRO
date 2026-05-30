// ============================================================================
// admin · /admin/material-library/:id — Vista read-only de un temario
// ----------------------------------------------------------------------------
// SOLO super-admin. Reusamos los providers existentes de subjects (que ya
// devuelven datos del subject elegido) -- gracias a las policies SELECT del
// super-admin que anyade la migracion 0078, no se filtran por owner.
//
// CRITICAL: aqui NO se llama jamas a metodos mutadores del datasource.
// La pagina solo presenta. No hay botones de regenerar / validar /
// generar quiz / crear notas / editar / borrar / chat. Es un visor
// para verificar que material esta cargado en el sistema.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/markdown_text.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/features/subjects/application/subjects_providers.dart';
import 'package:myapp/features/subjects/domain/subject.dart';

class AdminSubjectViewPage extends ConsumerWidget {
  const AdminSubjectViewPage({required this.subjectId, super.key});

  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(adminSubjectProvider(subjectId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.popOrGo(RouteNames.adminMaterialLibrary),
        ),
        title: Text(l.adminMaterialLibrarySubjectTitle),
        actions: [
          // Badge "Read-only" visible siempre, recordando que no se puede
          // modificar nada desde aqui.
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: PremiumBadge(
              label: l.adminMaterialLibraryReadOnly,
              variant: PremiumBadgeVariant.info,
              icon: Icons.lock_outline,
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: AppLoadingState()),
        error: (e, _) => Center(
          child: AppErrorState(
            message: l.adminMaterialLibraryLoadError,
            detail: e.toString(),
            onRetry: () => ref.invalidate(adminSubjectProvider(subjectId)),
            retryLabel: l.actionRetry,
          ),
        ),
        data: (row) {
          if (row == null) {
            return Center(
              child: AppEmptyState(
                icon: Icons.error_outline,
                title: l.adminMaterialLibrarySubjectNotFound,
                message: l.adminMaterialLibrarySubjectNotFoundBody,
              ),
            );
          }
          return _AdminSubjectBody(row: row);
        },
      ),
    );
  }
}

class _AdminSubjectBody extends ConsumerStatefulWidget {
  const _AdminSubjectBody({required this.row});

  final AdminSubjectRow row;

  @override
  ConsumerState<_AdminSubjectBody> createState() => _AdminSubjectBodyState();
}

class _AdminSubjectBodyState extends ConsumerState<_AdminSubjectBody> {
  String? _selectedNodeId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = widget.row.subject;
    final localeCode = Localizations.localeOf(context).languageCode;
    final dateFmt = DateFormat.yMMMMd(localeCode);
    final nodesAsync = ref.watch(indexNodesProvider(s.id));
    final docsAsync = ref.watch(subjectDocumentsProvider(s.id));
    final flashAsync = ref.watch(flashcardsProvider(s.id));
    final quizAsync = ref.watch(quizQuestionsProvider(s.id));
    final tfAsync = ref.watch(tfQuestionsProvider(s.id));
    final essayAsync = ref.watch(essayQuestionsProvider(s.id));
    final attemptsAsync = ref.watch(examAttemptsProvider(s.id));
    final notesAsync = ref.watch(annotationsForSubjectProvider(s.id));
    final guideAsync = ref.watch(studyGuideProvider(s.id));
    final cramAsync = ref.watch(cramProvider(s.id));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Header con metadata ───
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            color: context.colors.primary,
                            size: 26,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              s.title.isEmpty ? '—' : s.title,
                              style: context.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      AppSpacing.gapSm,
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _MetaItem(
                            icon: Icons.person_outline,
                            label: l.adminMaterialLibraryColOwner,
                            value: widget.row.ownerLabel,
                          ),
                          if (widget.row.ownerEmail != null)
                            _MetaItem(
                              icon: Icons.mail_outline,
                              label: 'Email',
                              value: widget.row.ownerEmail!,
                            ),
                          if (s.language != null)
                            _MetaItem(
                              icon: Icons.language,
                              label: l.adminMaterialLibraryColLanguage,
                              value: s.language!.toUpperCase(),
                            ),
                          _MetaItem(
                            icon: Icons.list_alt_outlined,
                            label: l.adminMaterialLibraryColStatus,
                            value: _statusLabel(context, s),
                          ),
                          if (s.createdAt != null)
                            _MetaItem(
                              icon: Icons.event_outlined,
                              label: l.adminMaterialLibraryColCreated,
                              value: dateFmt.format(s.createdAt!.toLocal()),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapMd,
              // ─── Stats row ───
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _StatsRow(
                  docs: widget.row.docsCount,
                  nodes: widget.row.nodesCount,
                  flashcards: flashAsync.maybeWhen(
                    data: (v) => v.length,
                    orElse: () => 0,
                  ),
                  quiz: quizAsync.maybeWhen(
                    data: (v) => v.length,
                    orElse: () => 0,
                  ),
                  tf: tfAsync.maybeWhen(
                    data: (v) => v.length,
                    orElse: () => 0,
                  ),
                  essay: essayAsync.maybeWhen(
                    data: (v) => v.length,
                    orElse: () => 0,
                  ),
                  attempts: attemptsAsync.maybeWhen(
                    data: (v) => v.length,
                    orElse: () => 0,
                  ),
                  notes: notesAsync.maybeWhen(
                    data: (v) => v.length,
                    orElse: () => 0,
                  ),
                ),
              ),
              AppSpacing.gapMd,
              // ─── Documentos ───
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        title: l.adminMaterialLibrarySectionDocuments,
                        compact: true,
                      ),
                      AppSpacing.gapSm,
                      docsAsync.when(
                        loading: () => const AppLoadingState(),
                        error: (e, _) => Text(
                          e.toString(),
                          style: TextStyle(color: context.colors.error),
                        ),
                        data: (docs) {
                          if (docs.isEmpty) {
                            return Text(
                              l.adminMaterialLibraryNoDocs,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            );
                          }
                          return Column(
                            children: [
                              for (final d in docs)
                                ListTile(
                                  dense: true,
                                  leading:
                                      const Icon(Icons.description_outlined),
                                  title: Text(d.fileName ?? d.storagePath),
                                  subtitle: Text(
                                    '${d.mimeType ?? '—'} · ${_docStatusLabel(context, d.status)}',
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
              AppSpacing.gapMd,
              // ─── Indice + contenido sec. seleccionada ───
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        title: l.adminMaterialLibrarySectionIndex,
                        compact: true,
                      ),
                      AppSpacing.gapSm,
                      nodesAsync.when(
                        loading: () => const AppLoadingState(),
                        error: (e, _) => Text(
                          e.toString(),
                          style: TextStyle(color: context.colors.error),
                        ),
                        data: (nodes) {
                          if (nodes.isEmpty) {
                            return Text(
                              l.adminMaterialLibraryNoIndex,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            );
                          }
                          return LayoutBuilder(
                            builder: (context, c) {
                              final wide = c.maxWidth >= 720;
                              final indexCol = SizedBox(
                                width: wide ? 320 : double.infinity,
                                height: wide ? 500 : null,
                                child: _SelectableIndexTree(
                                  nodes: nodes,
                                  selectedId: _selectedNodeId,
                                  onSelect: (id) =>
                                      setState(() => _selectedNodeId = id),
                                ),
                              );
                              final contentCol = SizedBox(
                                height: wide ? 500 : null,
                                child: _NodeContentReadOnly(
                                  subjectId: s.id,
                                  selectedNodeId: _selectedNodeId,
                                ),
                              );
                              if (wide) {
                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    indexCol,
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(child: contentCol),
                                  ],
                                );
                              }
                              return Column(
                                children: [
                                  indexCol,
                                  AppSpacing.gapMd,
                                  contentCol,
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapMd,
              // ─── Quiz / V-F / Essay ───
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        title: l.adminMaterialLibrarySectionTests,
                        compact: true,
                      ),
                      AppSpacing.gapSm,
                      _ListPreview<QuizQuestion>(
                        title: l.adminMaterialLibraryQuiz,
                        async: quizAsync,
                        labelOf: (q) => q.question,
                      ),
                      AppSpacing.gapSm,
                      _ListPreview<TfQuestion>(
                        title: l.adminMaterialLibraryTf,
                        async: tfAsync,
                        labelOf: (q) => q.statement,
                      ),
                      AppSpacing.gapSm,
                      _ListPreview<EssayQuestion>(
                        title: l.adminMaterialLibraryEssay,
                        async: essayAsync,
                        labelOf: (q) => q.question,
                      ),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapMd,
              // ─── Flashcards + Notas ───
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        title: l.adminMaterialLibrarySectionOther,
                        compact: true,
                      ),
                      AppSpacing.gapSm,
                      _ListPreview<Flashcard>(
                        title: l.adminMaterialLibraryFlashcards,
                        async: flashAsync,
                        labelOf: (f) => f.front,
                      ),
                      AppSpacing.gapSm,
                      _ListPreview<Annotation>(
                        title: l.adminMaterialLibraryNotes,
                        async: notesAsync,
                        labelOf: (a) => a.body,
                      ),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapMd,
              // ─── Guia / Cram (textos completos read-only) ───
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        title: l.adminMaterialLibrarySectionGuides,
                        compact: true,
                      ),
                      AppSpacing.gapSm,
                      _CachedTextSection(
                        title: l.adminMaterialLibraryStudyGuide,
                        async: guideAsync,
                      ),
                      AppSpacing.gapSm,
                      _CachedTextSection(
                        title: l.adminMaterialLibraryCram,
                        async: cramAsync,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: context.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: context.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.docs,
    required this.nodes,
    required this.flashcards,
    required this.quiz,
    required this.tf,
    required this.essay,
    required this.attempts,
    required this.notes,
  });

  final int docs;
  final int nodes;
  final int flashcards;
  final int quiz;
  final int tf;
  final int essay;
  final int attempts;
  final int notes;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final items = <(IconData, String, int)>[
      (Icons.description_outlined, l.adminMaterialLibraryColDocs, docs),
      (Icons.list_alt_outlined, l.adminMaterialLibraryColNodes, nodes),
      (Icons.style_outlined, l.adminMaterialLibraryFlashcards, flashcards),
      (Icons.quiz_outlined, l.adminMaterialLibraryQuiz, quiz),
      (Icons.rule_outlined, l.adminMaterialLibraryTf, tf),
      (Icons.article_outlined, l.adminMaterialLibraryEssay, essay),
      (Icons.history_outlined, l.adminMaterialLibraryAttempts, attempts),
      (Icons.sticky_note_2_outlined, l.adminMaterialLibraryNotes, notes),
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final it in items)
          _StatChip(icon: it.$1, label: it.$2, value: it.$3),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: context.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableIndexTree extends StatelessWidget {
  const _SelectableIndexTree({
    required this.nodes,
    required this.selectedId,
    required this.onSelect,
  });

  final List<IndexNode> nodes;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // El CollapsibleIndexTree existente solo muestra (sin seleccion). Para el
    // admin necesitamos seleccion para ver el contenido. Pintamos una version
    // sencilla con ListView indentado por depth.
    final byDepth = [...nodes]
      ..sort((a, b) {
        final d = a.depth.compareTo(b.depth);
        if (d != 0) return d;
        return a.position.compareTo(b.position);
      });
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: context.colors.outline.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: byDepth.length,
        itemBuilder: (_, i) {
          final n = byDepth[i];
          final selected = n.id == selectedId;
          return InkWell(
            onTap: () => onSelect(n.id),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                12.0 + (n.depth * 16),
                8,
                12,
                8,
              ),
              color: selected
                  ? context.colors.primary.withValues(alpha: 0.1)
                  : null,
              child: Row(
                children: [
                  Icon(
                    n.depth == 0
                        ? Icons.folder_outlined
                        : Icons.fiber_manual_record,
                    size: n.depth == 0 ? 14 : 8,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      n.title,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(
                        fontWeight: selected || n.depth == 0
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NodeContentReadOnly extends ConsumerWidget {
  const _NodeContentReadOnly({
    required this.subjectId,
    required this.selectedNodeId,
  });

  final String subjectId;
  final String? selectedNodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (selectedNodeId == null) {
      return Center(
        child: Text(
          l.adminMaterialLibrarySelectNode,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    }
    final explained = ref.watch(
      nodeContentProvider(
        (nodeId: selectedNodeId!, kind: 'explained'),
      ),
    );
    final summary = ref.watch(
      nodeContentProvider(
        (nodeId: selectedNodeId!, kind: 'summary'),
      ),
    );
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            tabs: [
              Tab(text: l.adminMaterialLibraryExplained),
              Tab(text: l.adminMaterialLibrarySummary),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ContentPane(async: explained),
                _ContentPane(async: summary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentPane extends StatelessWidget {
  const _ContentPane({required this.async});
  final AsyncValue<String?> async;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => Center(
        child: Text(
          e.toString(),
          style: TextStyle(color: context.colors.error),
        ),
      ),
      data: (txt) {
        if (txt == null || txt.trim().isEmpty) {
          return Center(
            child: Text(
              l.adminMaterialLibraryNoContent,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: MarkdownText(txt),
        );
      },
    );
  }
}

class _ListPreview<T> extends StatelessWidget {
  const _ListPreview({
    required this.title,
    required this.async,
    required this.labelOf,
  });

  final String title;
  final AsyncValue<List<T>> async;
  final String Function(T item) labelOf;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            async.maybeWhen(
              data: (rows) => Text(
                '(${rows.length})',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (e, _) => Text(
            e.toString(),
            style: TextStyle(color: context.colors.error),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return Text(
                l.adminMaterialLibraryEmptyList,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              );
            }
            final preview = rows.take(5).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in preview)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${_oneLine(labelOf(r))}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall,
                    ),
                  ),
                if (rows.length > preview.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l.adminMaterialLibraryMoreItems(
                        rows.length - preview.length,
                      ),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

class _CachedTextSection extends StatelessWidget {
  const _CachedTextSection({required this.title, required this.async});
  final String title;
  final AsyncValue<String?> async;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        async.when(
          loading: () =>
              const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => Text(
            e.toString(),
            style: TextStyle(color: context.colors.error),
          ),
          data: (txt) {
            if (txt == null || txt.trim().isEmpty) {
              return Text(
                l.adminMaterialLibraryNoContent,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: MarkdownText(txt),
              ),
            );
          },
        ),
      ],
    );
  }
}

String _statusLabel(BuildContext context, Subject s) {
  final l = context.l10n;
  if (s.indexLocked) return l.myMaterialStatusValidated;
  switch (s.indexStatus) {
    case IndexStatus.ready:
      return l.myMaterialStatusGenerated;
    case IndexStatus.generating:
      return l.myMaterialStatusGenerating;
    case IndexStatus.failed:
      return l.myMaterialStatusFailed;
    case IndexStatus.none:
      return l.myMaterialStatusNone;
  }
}

String _docStatusLabel(BuildContext context, DocStatus s) {
  switch (s) {
    case DocStatus.queued:
      return 'queued';
    case DocStatus.processing:
      return 'processing';
    case DocStatus.ready:
      return 'ready';
    case DocStatus.failed:
      return 'failed';
  }
}
