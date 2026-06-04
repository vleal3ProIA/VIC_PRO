// ============================================================================
// subjects · /mis-temarios/:id/:kind — vista por tipo (drill-down nivel 2)
// ----------------------------------------------------------------------------
// Segundo nivel del drill-down de Mi Material. Recibe el subjectId y la
// "kind" (slug en URL — documents, index, views, quiz, tf, essay, flashcards,
// notes, mindmap, guide, cram, mock, history). Renderiza una vista
// especifica por kind reutilizando los providers existentes.
//
// Tras la extracción de runners (TestRunnerDialog/TfRunnerDialog/MockExamView/
// MindMapView/TfView a `widgets/runners/`), las kinds que ANTES redirigían al
// Panel (quiz, tf, mock, mindmap) renderizan AHORA el runner real INLINE.
// El resto (notes/essay/history/guide/cram/flashcards list/documents/index/
// views) sigue siendo lectura ligera leyendo los mismos providers.
//
// El StudyPanel mantiene su flujo original — esto es complementario: cualquier
// kind puede abrirse desde /mis-temarios/<id>/<kind> sin tocar /home.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/markdown_text.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/subjects_providers.dart';
import '../../domain/subject.dart';
import '../widgets/runners/mind_map_view.dart';
import '../widgets/runners/mock_exam_view.dart';
import '../widgets/runners/tf_view.dart';
import '../widgets/saved_tests_library.dart';

/// Alto fijo (en lógicas) reservado al runner inline (test, V-F, mapa mental,
/// simulacro). Los runners usan `ListView`/`Stack` internamente y necesitan
/// limites verticales al vivir dentro de un `SingleChildScrollView`.
const double _kRunnerHeight = 640;

/// Identificador estable del tipo de contenido que estamos viendo. El `slug`
/// es el segmento de URL `:kind` (ASCII estable, no traducible) — usar enum
/// evita strings magicos en el router y permite `switch` exhaustivo.
enum MyMaterialKind {
  documents('documents'),
  // NOTA: el nombre de Dart es `indexNodes` (no `index`) para evitar colision
  // con `Enum.index` (el getter int sintetico de cada valor). El slug de URL
  // sigue siendo "index" — eso es lo que el user pide ver en la URL.
  indexNodes('index'),
  views('views'),
  quiz('quiz'),
  tf('tf'),
  essay('essay'),
  flashcards('flashcards'),
  notes('notes'),
  mindmap('mindmap'),
  guide('guide'),
  cram('cram'),
  mock('mock'),
  history('history');

  const MyMaterialKind(this.slug);
  final String slug;

  static MyMaterialKind? fromSlug(String s) {
    for (final k in MyMaterialKind.values) {
      if (k.slug == s) return k;
    }
    return null;
  }
}

class MyMaterialKindPage extends ConsumerWidget {
  const MyMaterialKindPage({
    required this.subjectId,
    required this.kind,
    super.key,
  });

  final String subjectId;
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final parsed = MyMaterialKind.fromSlug(kind);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          // Fallback: si llegan por URL directa, volver al dashboard del
          // temario (un nivel arriba) en vez de a la raíz.
          onPressed: () => context.popOrGo(RouteNames.myMaterialSubject),
        ),
        title: Text(parsed == null ? '—' : _kindLabel(context, parsed)),
        actions: [
          TextButton.icon(
            onPressed: () => context.goNamed(
              RouteNames.home,
              queryParameters: {'subjectId': subjectId},
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(l.myMaterialSubjectOpenPanel),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: parsed == null
          ? Center(
              child: AppEmptyState(
                icon: Icons.help_outline,
                title: l.myMaterialSubjectNotFound,
                message: l.myMaterialKindEmpty,
              ),
            )
          : _KindBody(subjectId: subjectId, kind: parsed),
    );
  }
}

String _kindLabel(BuildContext context, MyMaterialKind k) {
  final l = context.l10n;
  switch (k) {
    case MyMaterialKind.documents:
      return l.myMaterialKindDocuments;
    case MyMaterialKind.indexNodes:
      return l.myMaterialKindIndex;
    case MyMaterialKind.views:
      return l.myMaterialKindViews;
    case MyMaterialKind.quiz:
      return l.myMaterialKindQuiz;
    case MyMaterialKind.tf:
      return l.myMaterialKindTf;
    case MyMaterialKind.essay:
      return l.myMaterialKindEssay;
    case MyMaterialKind.flashcards:
      return l.myMaterialKindFlashcards;
    case MyMaterialKind.notes:
      return l.myMaterialKindNotes;
    case MyMaterialKind.mindmap:
      return l.myMaterialKindMindmap;
    case MyMaterialKind.guide:
      return l.myMaterialKindGuide;
    case MyMaterialKind.cram:
      return l.myMaterialKindCram;
    case MyMaterialKind.mock:
      return l.myMaterialKindMock;
    case MyMaterialKind.history:
      return l.myMaterialKindHistory;
  }
}

class _KindBody extends ConsumerWidget {
  const _KindBody({required this.subjectId, required this.kind});

  final String subjectId;
  final MyMaterialKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final subjects = ref.watch(subjectsListProvider);
    return subjects.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => Center(
        child: AppErrorState(
          message: l.errorGeneric,
          onRetry: () => ref.invalidate(subjectsListProvider),
          retryLabel: l.actionRetry,
        ),
      ),
      data: (subjects) {
        final subject = subjects.where((s) => s.id == subjectId).firstOrNull;
        if (subject == null) {
          return Center(
            child: AppEmptyState(
              icon: Icons.help_outline,
              title: l.myMaterialSubjectNotFound,
              message: l.myMaterialEmptyBody,
            ),
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    title: _kindLabel(context, kind),
                    subtitle: subject.title.isEmpty
                        ? l.myMaterialUntitled
                        : subject.title,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: _KindContent(subject: subject, kind: kind),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Selector central: por kind, renderiza la vista adecuada. Cada vista es
/// un widget aislado que lee sus propios providers — asi anyadir/cambiar una
/// kind es local.
class _KindContent extends StatelessWidget {
  const _KindContent({required this.subject, required this.kind});

  final Subject subject;
  final MyMaterialKind kind;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case MyMaterialKind.documents:
        return _DocumentsCard(subjectId: subject.id);
      case MyMaterialKind.indexNodes:
        return _IndexCard(subjectId: subject.id);
      case MyMaterialKind.views:
        return _ViewsCard(subjectId: subject.id);
      case MyMaterialKind.quiz:
        return _QuizRunnerCard(subjectId: subject.id);
      case MyMaterialKind.tf:
        return SavedTestsLibrary(
          subjectId: subject.id,
          kind: SavedTestKind.tf,
        );
      case MyMaterialKind.essay:
        return SavedTestsLibrary(
          subjectId: subject.id,
          kind: SavedTestKind.essay,
        );
      case MyMaterialKind.flashcards:
        return _FlashcardsListCard(subjectId: subject.id);
      case MyMaterialKind.notes:
        return _NotesCard(subjectId: subject.id);
      case MyMaterialKind.mindmap:
        return _MindMapRunnerCard(subjectId: subject.id);
      case MyMaterialKind.guide:
        return _GuideCard(subjectId: subject.id);
      case MyMaterialKind.cram:
        return _CramCard(subjectId: subject.id);
      case MyMaterialKind.mock:
        return _MockRunnerCard(subjectId: subject.id);
      case MyMaterialKind.history:
        return _HistoryListCard(subjectId: subject.id);
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Helpers de UI: empty-state estandar + CTA "Abrir en el Panel" reutilizable.
// ════════════════════════════════════════════════════════════════════════════

/// Empty state estandar para todas las kinds. Texto generico + CTA al Panel.
/// Centralizado para que cambiar el copy en 1 sitio actualice las 13 vistas.
class _KindEmpty extends StatelessWidget {
  const _KindEmpty({required this.subjectId, required this.icon});
  final String subjectId;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AppEmptyState(
      icon: icon,
      // Sin `title`: el `message` ya lleva la frase completa con CTA implicito.
      message: l.myMaterialKindEmpty,
      action: FilledButton.icon(
        onPressed: () => context.goNamed(
          RouteNames.home,
          queryParameters: {'subjectId': subjectId},
        ),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(l.myMaterialKindOpenInPanel),
      ),
    );
  }
}

/// CTA inline "Abrir en el Panel". Tras la extracción de runners se sigue
/// usando para las kinds que aun no tienen runner inline (flashcards, cuya
/// vista de repaso `_FlashcardsView` continua en `subject_study_panel.dart`).
class _RunInPanelCta extends StatelessWidget {
  const _RunInPanelCta({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.play_circle_outline, color: context.colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l.myMaterialKindRunInPanel,
              style: context.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            onPressed: () => context.goNamed(
              RouteNames.home,
              queryParameters: {'subjectId': subjectId},
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(l.myMaterialKindOpenInPanel),
          ),
        ],
      ),
    );
  }
}

/// Wrapper estandar para una AsyncValue: loading / error / data con empty.
/// Centraliza el patron repetido 13 veces en este archivo.
class _AsyncWrap<T> extends ConsumerWidget {
  const _AsyncWrap({
    required this.provider,
    required this.builder,
    required this.onEmpty,
    required this.isEmpty,
    super.key,
  });

  final ProviderListenable<AsyncValue<T>> provider;
  final Widget Function(T data) builder;
  final Widget onEmpty;
  final bool Function(T data) isEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(provider);
    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => Center(
        child: AppErrorState(
          message: l.errorGeneric,
        ),
      ),
      data: (d) => isEmpty(d) ? onEmpty : builder(d),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Vistas concretas por kind. Cada una se documenta brevemente con su origen.
// ════════════════════════════════════════════════════════════════════════════

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      child: _AsyncWrap<List<SubjectDocument>>(
        provider: subjectDocumentsProvider(subjectId),
        isEmpty: (v) => v.isEmpty,
        onEmpty: _KindEmpty(
          subjectId: subjectId,
          icon: Icons.cloud_outlined,
        ),
        builder: (docs) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: l.myMaterialKindDocuments, compact: true),
            AppSpacing.gapSm,
            for (final d in docs)
              ListTile(
                dense: true,
                leading: const Icon(Icons.description_outlined),
                title: Text(d.fileName ?? d.storagePath),
                subtitle: Text(
                  '${d.mimeType ?? '—'} · ${d.status.name}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IndexCard extends StatelessWidget {
  const _IndexCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      child: _AsyncWrap<List<IndexNode>>(
        provider: indexNodesProvider(subjectId),
        isEmpty: (v) => v.where((n) => n.parentId != null).isEmpty,
        onEmpty: _KindEmpty(
          subjectId: subjectId,
          icon: Icons.menu_book_outlined,
        ),
        builder: (nodes) {
          // Ordenamos por depth y position para mostrar el arbol "aplanado"
          // con indentacion. Es una lectura read-only — la navegacion en
          // arbol de verdad esta en el Panel.
          final tree = [...nodes]
            ..sort((a, b) {
              final d = a.depth.compareTo(b.depth);
              if (d != 0) return d;
              return a.position.compareTo(b.position);
            });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: l.myMaterialKindIndex, compact: true),
              AppSpacing.gapSm,
              for (final n in tree)
                Padding(
                  padding: EdgeInsets.only(
                    left: 8 + n.depth * 16.0,
                    top: 4,
                    bottom: 4,
                  ),
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall?.copyWith(
                            fontWeight: n.depth == 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Vistas (explicado/resumen) por seccion. El user elige la seccion del
/// dropdown; cargamos los 2 contenidos via `nodeContentProvider`.
class _ViewsCard extends ConsumerStatefulWidget {
  const _ViewsCard({required this.subjectId});
  final String subjectId;

  @override
  ConsumerState<_ViewsCard> createState() => _ViewsCardState();
}

class _ViewsCardState extends ConsumerState<_ViewsCard>
    with SingleTickerProviderStateMixin {
  String? _selectedNodeId;
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      child: _AsyncWrap<List<IndexNode>>(
        provider: indexNodesProvider(widget.subjectId),
        isEmpty: (v) => v.where((n) => n.parentId != null).isEmpty,
        onEmpty: _KindEmpty(
          subjectId: widget.subjectId,
          icon: Icons.auto_stories_outlined,
        ),
        builder: (nodes) {
          final sections =
              nodes.where((n) => n.parentId != null).toList()
                ..sort((a, b) => a.position.compareTo(b.position));
          final selected = _selectedNodeId ??
              (sections.isNotEmpty ? sections.first.id : null);
          if (selected == null) {
            return _KindEmpty(
              subjectId: widget.subjectId,
              icon: Icons.auto_stories_outlined,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: l.myMaterialKindViews, compact: true),
              AppSpacing.gapSm,
              DropdownButtonFormField<String>(
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: l.myMaterialKindSelectSection,
                ),
                items: [
                  for (final n in sections)
                    DropdownMenuItem(value: n.id, child: Text(n.title)),
                ],
                onChanged: (v) => setState(() => _selectedNodeId = v),
              ),
              AppSpacing.gapMd,
              TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: l.myMaterialKindOriginal),
                  Tab(text: l.myMaterialKindExplained),
                  Tab(text: l.myMaterialKindSummary),
                ],
              ),
              SizedBox(
                height: 480,
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _NodeContentPane(
                      provider: nodeContentProvider(
                        (nodeId: selected, kind: 'original'),
                      ),
                    ),
                    _NodeContentPane(
                      provider: nodeContentProvider(
                        (nodeId: selected, kind: 'explained'),
                      ),
                    ),
                    _NodeContentPane(
                      provider: nodeContentProvider(
                        (nodeId: selected, kind: 'summary'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NodeContentPane extends ConsumerWidget {
  const _NodeContentPane({required this.provider});
  final ProviderListenable<AsyncValue<String?>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(provider);
    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => Center(
        child: Text(
          l.errorGeneric,
          style: TextStyle(color: context.colors.error),
        ),
      ),
      data: (txt) {
        if (txt == null || txt.trim().isEmpty) {
          return Center(
            child: Text(
              l.myMaterialKindEmpty,
              textAlign: TextAlign.center,
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

/// Quiz / Test: configurador inline (mismo que el Panel) — secciones,
/// nº preguntas, tiempo y penalización. Al pulsar Empezar abre el modal
/// difuminado con el [TestRunnerDialog]. Necesita los nodes del índice para
/// el ámbito; cargamos `indexNodesProvider` y delegamos a [MockExamView].
class _QuizRunnerCard extends ConsumerWidget {
  const _QuizRunnerCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: _kRunnerHeight,
        child: _AsyncWrap<List<IndexNode>>(
          provider: indexNodesProvider(subjectId),
          isEmpty: (v) => v.where((n) => n.parentId != null).isEmpty,
          onEmpty: _KindEmpty(subjectId: subjectId, icon: Icons.quiz_outlined),
          builder: (nodes) => MockExamView(
            subjectId: subjectId,
            nodes: nodes,
            // En /mis-temarios no hay columna índice que sincronizar; el salto
            // al material se hace via la URL si el user quiere ir al Panel.
            onSelectNode: (_) {},
          ),
        ),
      ),
    );
  }
}

/// Verdadero/Falso: configurador inline + [TfRunnerDialog] vía [TfView].
// ignore: unused_element
class _TfRunnerCard extends ConsumerWidget {
  const _TfRunnerCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: _kRunnerHeight,
        child: _AsyncWrap<List<IndexNode>>(
          provider: indexNodesProvider(subjectId),
          isEmpty: (v) => v.where((n) => n.parentId != null).isEmpty,
          onEmpty: _KindEmpty(subjectId: subjectId, icon: Icons.rule),
          builder: (nodes) => TfView(subjectId: subjectId, nodes: nodes),
        ),
      ),
    );
  }
}

/// Para essay mostramos la lista con pregunta + respuesta colapsable (la
/// respuesta modelo puede ser larga). Read-only — el user no edita aqui.
// ignore: unused_element
class _EssayListCard extends StatelessWidget {
  const _EssayListCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      child: _AsyncWrap<List<EssayQuestion>>(
        provider: essayQuestionsProvider(subjectId),
        isEmpty: (v) => v.isEmpty,
        onEmpty: _KindEmpty(subjectId: subjectId, icon: Icons.edit_note),
        builder: (qs) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: l.myMaterialKindEssay, compact: true),
            AppSpacing.gapSm,
            for (final q in qs)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  q.question,
                  style: context.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: MarkdownText(q.answer),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FlashcardsListCard extends StatelessWidget {
  const _FlashcardsListCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RunInPanelCta(subjectId: subjectId),
        AppSpacing.gapMd,
        PremiumCard(
          child: _AsyncWrap<List<Flashcard>>(
            provider: flashcardsProvider(subjectId),
            isEmpty: (v) => v.isEmpty,
            onEmpty: _KindEmpty(
              subjectId: subjectId,
              icon: Icons.style_outlined,
            ),
            builder: (cards) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: l.myMaterialKindFlashcards, compact: true),
                AppSpacing.gapSm,
                for (final c in cards)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      c.front,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Text(
                          c.back,
                          style: context.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Notas agregadas del temario completo. Read-only en este flow (la edicion
/// sigue siendo por seccion en el StudyPanel — aqui es solo consulta rapida).
class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      child: _AsyncWrap<List<Annotation>>(
        provider: annotationsForSubjectProvider(subjectId),
        isEmpty: (v) => v.isEmpty,
        onEmpty: _KindEmpty(
          subjectId: subjectId,
          icon: Icons.sticky_note_2_outlined,
        ),
        builder: (notes) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: l.myMaterialKindNotes, compact: true),
            AppSpacing.gapSm,
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    n.body,
                    style: context.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mapa mental navegable inline. Reutiliza el mismo widget del Panel
/// ([MindMapView]) — el `selectedId` queda en null aqui (no hay seleccion
/// previa al entrar) y `onSelectNode` es no-op porque no hay columna indice
/// que sincronizar; las burbujas son visuales/clicables solo para expandir.
class _MindMapRunnerCard extends StatelessWidget {
  const _MindMapRunnerCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: _kRunnerHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: MindMapView(
            subjectId: subjectId,
            selectedId: null,
            onSelectNode: (_) {},
          ),
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      child: _AsyncWrap<String?>(
        provider: studyGuideProvider(subjectId),
        isEmpty: (v) => v == null || v.trim().isEmpty,
        onEmpty: _KindEmpty(subjectId: subjectId, icon: Icons.menu_book),
        builder: (txt) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: l.myMaterialKindGuide, compact: true),
            AppSpacing.gapSm,
            MarkdownText(txt!),
          ],
        ),
      ),
    );
  }
}

class _CramCard extends StatelessWidget {
  const _CramCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      child: _AsyncWrap<String?>(
        provider: cramProvider(subjectId),
        isEmpty: (v) => v == null || v.trim().isEmpty,
        onEmpty: _KindEmpty(subjectId: subjectId, icon: Icons.flash_on_outlined),
        builder: (txt) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: l.myMaterialKindCram, compact: true),
            AppSpacing.gapSm,
            MarkdownText(txt!),
          ],
        ),
      ),
    );
  }
}

/// Mock = biblioteca de tests guardados del temario.
///
/// Muestra:
///   1. Banner con el total de preguntas en el banco + botón "Hacer test de
///      TODAS las preguntas" (crea un SavedTest con todas y arranca).
///   2. Lista de SavedTest del usuario para este temario, con título, fecha,
///      número de preguntas y última nota. Click = arrancar (modal cantidad
///      → runner). Cada fila tiene popmenu Renombrar / Borrar.
///
/// El configurador con selección de secciones para CREAR un nuevo test
/// (MockExamView) sigue viviendo en el Panel `/home` (con subjectId).
class _MockRunnerCard extends StatelessWidget {
  const _MockRunnerCard({required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    return SavedTestsLibrary(subjectId: subjectId, kind: SavedTestKind.mock);
  }
}

/// Historial: lista de attempts ordenados (mas reciente primero) con grado.
/// Reusa la idea del `_HistoryView` del Panel pero sin grafica.
class _HistoryListCard extends StatelessWidget {
  const _HistoryListCard({required this.subjectId});
  final String subjectId;

  static String _fmtDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      child: _AsyncWrap<List<ExamAttempt>>(
        provider: examAttemptsProvider(subjectId),
        isEmpty: (v) => v.isEmpty,
        onEmpty: _KindEmpty(subjectId: subjectId, icon: Icons.history),
        builder: (attempts) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: l.myMaterialKindHistory, compact: true),
            AppSpacing.gapSm,
            for (final a in attempts)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.history,
                  color: a.grade >= 5
                      ? Colors.green.shade400
                      : context.colors.error,
                ),
                title: Text(
                  '${a.grade.toStringAsFixed(2)} / 10  ·  '
                  '${a.correct}/${a.total}',
                ),
                subtitle: Text(_fmtDateTime(a.createdAt)),
              ),
          ],
        ),
      ),
    );
  }
}
