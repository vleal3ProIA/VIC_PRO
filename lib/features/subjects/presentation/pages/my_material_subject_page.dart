// ============================================================================
// subjects · /mis-temarios/:id — dashboard del temario (drill-down nivel 1)
// ----------------------------------------------------------------------------
// Cuando el user pulsa una card en /mis-temarios, llega aqui — NO al
// StudyPanel completo (/home). Esto es un acceso rapido tipo
// "panel administrativo del temario" con contadores por tipo de contenido.
// Cada card del grid abre /mis-temarios/:id/:kind donde el user ve la
// lista concreta y, segun el tipo, puede ejecutar / crear / abrir.
//
// El StudyPanel original sigue intacto en /home — quien quiera la vista
// completa de 3 columnas (índice · contenido · estudio) la sigue teniendo
// allí. Este drill-down es ADITIVO, no sustitutivo. Lo dejamos como flow
// paralelo porque el user pidió un acceso rápido y centrado en lo que ya
// está generado del material, sin pasar por la pantalla compleja del Panel.
//
// **Decisión arquitectónica clave**: NO importamos `subject_study_panel.dart`
// (sus widgets son `private _Xxx` y refactorizarlos a public seria invasivo
// — riesgo alto de regresion en ~6000 lineas). En su lugar leemos los MISMOS
// providers (`flashcardsProvider`, `quizQuestionsProvider`, etc.) y pintamos
// vistas más simples; ver `my_material_kind_page.dart`.
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
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/subjects_providers.dart';
import '../../domain/subject.dart';
import 'my_material_kind_page.dart' show MyMaterialKind;

/// Página dashboard del temario en el flujo "Mi Material". Muestra un grid
/// de [_KindStatCard]s — uno por tipo de contenido — con su contador y el
/// link al detalle (`/mis-temarios/:id/:kind`).
class MyMaterialSubjectPage extends ConsumerWidget {
  const MyMaterialSubjectPage({required this.subjectId, super.key});

  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(subjectsListProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.myMaterial),
        ),
        title: Text(l.myMaterialTitle),
        actions: [
          // Botón de escape al Panel completo: por si el user quiere la vista
          // tradicional de 3 columnas para chat / generar contenido nuevo /
          // etc., damos un atajo bien visible. La cookie del Panel (last
          // subject) ya recuerda el seleccionado.
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
          // Buscar el subject en la lista del user. Si no aparece, o bien el
          // id no existe o no pertenece al user (RLS lo habria filtrado de
          // todos modos). Mostramos un empty-state amigable, NO un crash.
          final subject = subjects.where((s) => s.id == subjectId).firstOrNull;
          if (subject == null) {
            return Center(
              child: AppEmptyState(
                icon: Icons.help_outline,
                title: l.myMaterialSubjectNotFound,
                message: l.myMaterialEmptyBody,
                action: TextButton.icon(
                  onPressed: () => context.goNamed(RouteNames.myMaterial),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(l.myMaterialSubjectBack),
                ),
              ),
            );
          }
          return _DashboardBody(subject: subject);
        },
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final id = subject.id;

    // Cargamos todos los providers de contadores en paralelo. Cada
    // `.maybeWhen(data: ..., orElse: 0)` deja la card "viva" mientras
    // todavia se esta cargando — los contadores se rellenan a medida que
    // resuelven. Es mas amigable que esperar a que TODOS resuelvan a la vez.
    final docs = ref.watch(subjectDocumentsProvider(id));
    final nodes = ref.watch(indexNodesProvider(id));
    final aiNodeIds = ref.watch(aiContentNodeIdsProvider(id));
    final flashcards = ref.watch(flashcardsProvider(id));
    final examQs = ref.watch(examQuestionsProvider(id));
    final tfQs = ref.watch(tfQuestionsProvider(id));
    final essayQs = ref.watch(essayQuestionsProvider(id));
    final notes = ref.watch(annotationsForSubjectProvider(id));
    final attempts = ref.watch(examAttemptsProvider(id));
    final guide = ref.watch(studyGuideProvider(id));
    final cram = ref.watch(cramProvider(id));

    int data<T>(AsyncValue<T> a, int Function(T) f) =>
        a.maybeWhen(data: f, orElse: () => 0);

    // Contadores:
    //   - documentos: tal cual la lista.
    //   - índice: nodos NO-raíz (parent_id != null), porque la sección "raíz"
    //     es el contenedor virtual del temario, no una sección visible.
    //   - mapa mental: siempre disponible si hay índice (es una vista derivada,
    //     no datos generados); marcamos 1 si hay >0 secciones, 0 si no.
    //   - guía/cram: 1 si el provider devuelve no-null (existe contenido
    //     cacheado), 0 si no.
    //   - vistas (explicado/resumen): nº de nodos con contenido IA. Una misma
    //     sección genera explicado+resumen a la vez, por lo que `aiNodeIds`
    //     (set distinct) representa el nº de secciones con vista IA generada,
    //     que es el contador útil para el user.
    final docCount = data(docs, (v) => v.length);
    final sectionCount =
        data(nodes, (v) => v.where((n) => n.parentId != null).length);
    final aiCount = data(aiNodeIds, (v) => v.length);
    final mindmapCount = sectionCount > 0 ? 1 : 0;
    final guideCount = data(guide, (v) => (v != null && v.isNotEmpty) ? 1 : 0);
    final cramCount = data(cram, (v) => (v != null && v.isNotEmpty) ? 1 : 0);

    final items = <_KindItem>[
      _KindItem(
        kind: MyMaterialKind.documents,
        icon: Icons.cloud_outlined,
        label: l.myMaterialKindDocuments,
        count: docCount,
      ),
      _KindItem(
        kind: MyMaterialKind.indexNodes,
        icon: Icons.menu_book_outlined,
        label: l.myMaterialKindIndex,
        count: sectionCount,
      ),
      _KindItem(
        kind: MyMaterialKind.views,
        icon: Icons.auto_stories_outlined,
        label: l.myMaterialKindViews,
        count: aiCount,
      ),
      _KindItem(
        kind: MyMaterialKind.quiz,
        icon: Icons.quiz_outlined,
        label: l.myMaterialKindQuiz,
        count: data(examQs, (v) => v.length),
      ),
      _KindItem(
        kind: MyMaterialKind.tf,
        icon: Icons.rule,
        label: l.myMaterialKindTf,
        count: data(tfQs, (v) => v.length),
      ),
      _KindItem(
        kind: MyMaterialKind.essay,
        icon: Icons.edit_note,
        label: l.myMaterialKindEssay,
        count: data(essayQs, (v) => v.length),
      ),
      _KindItem(
        kind: MyMaterialKind.flashcards,
        icon: Icons.style_outlined,
        label: l.myMaterialKindFlashcards,
        count: data(flashcards, (v) => v.length),
      ),
      _KindItem(
        kind: MyMaterialKind.notes,
        icon: Icons.sticky_note_2_outlined,
        label: l.myMaterialKindNotes,
        count: data(notes, (v) => v.length),
      ),
      _KindItem(
        kind: MyMaterialKind.mindmap,
        icon: Icons.hub_outlined,
        label: l.myMaterialKindMindmap,
        count: mindmapCount,
      ),
      _KindItem(
        kind: MyMaterialKind.guide,
        icon: Icons.menu_book,
        label: l.myMaterialKindGuide,
        count: guideCount,
      ),
      _KindItem(
        kind: MyMaterialKind.cram,
        icon: Icons.flash_on_outlined,
        label: l.myMaterialKindCram,
        count: cramCount,
      ),
      _KindItem(
        kind: MyMaterialKind.mock,
        icon: Icons.fact_check_outlined,
        label: l.myMaterialKindMock,
        // El simulacro NO tiene datos persistentes — se configura en el momento.
        // Reportamos el nº de preguntas de exam disponibles como pool del
        // simulacro: si es 0 el user vera el empty state de la kind page.
        count: data(examQs, (v) => v.length),
      ),
      _KindItem(
        kind: MyMaterialKind.history,
        icon: Icons.history,
        label: l.myMaterialKindHistory,
        count: data(attempts, (v) => v.length),
      ),
    ];

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
                title:
                    subject.title.isEmpty ? l.myMaterialUntitled : subject.title,
                subtitle: l.myMaterialSubjectSubtitle,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                child: _KindsGrid(subjectId: subject.id, items: items),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Item de configuracion de una card del grid de kinds. Solo data; el render
/// vive en [_KindStatCard]. Mantenerlo separado deja el `build()` del body
/// declarativo: "para este subject, estos son los kinds y sus contadores".
class _KindItem {
  const _KindItem({
    required this.kind,
    required this.icon,
    required this.label,
    required this.count,
  });
  final MyMaterialKind kind;
  final IconData icon;
  final String label;
  final int count;
}

class _KindsGrid extends StatelessWidget {
  const _KindsGrid({required this.subjectId, required this.items});

  final String subjectId;
  final List<_KindItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        // 2 / 3 / 4 cols: mobile / tablet / desktop. Mismo breakpoint que el
        // grid de subjects en my_material_page para coherencia visual.
        final cols = w >= 1100 ? 4 : (w >= 800 ? 3 : 2);
        const gap = AppSpacing.md;
        final cardW = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final it in items)
              SizedBox(
                width: cardW,
                child: _KindStatCard(subjectId: subjectId, item: it),
              ),
          ],
        );
      },
    );
  }
}

class _KindStatCard extends StatelessWidget {
  const _KindStatCard({required this.subjectId, required this.item});

  final String subjectId;
  final _KindItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return PremiumCard(
      // Todos los kinds son siempre clicables — el user PUEDE entrar con 0
      // items para ver el empty-state y el CTA de "Abrir en el Panel para
      // generar". Disable visual seria confuso porque varios kinds (notas,
      // index, mindmap, documents) son utiles aun cuando count=0.
      onTap: () => context.goNamed(
        RouteNames.myMaterialSubjectKind,
        pathParameters: {'id': subjectId, 'kind': item.kind.slug},
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, color: scheme.primary, size: 26),
              const Spacer(),
              Text(
                '${item.count}',
                style: context.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: item.count == 0 ? scheme.onSurfaceVariant : null,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          AppSpacing.gapSm,
          Text(
            item.label,
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
