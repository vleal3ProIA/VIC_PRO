// ============================================================================
// subjects · SavedTestsLibrary
// ----------------------------------------------------------------------------
// Vista de "biblioteca de tests guardados" para `/mis-temarios/<id>/<kind>`.
// Funciona para los tres tipos: mock (A/B/C/D), tf (Verdadero/Falso) y
// essay (preguntas a desarrollar). El widget recibe [kind] y dispatchea:
//
//   - El banner del banco lee la tabla correspondiente
//     (`question_bank` / `tf_bank` / `essay_bank`) via el provider apropiado.
//   - Al pulsar "Hacer test de TODAS las preguntas" crea un SavedTest con
//     `kind` igual al que recibe y todas las preguntas del banco.
//   - Al pulsar "Realizar test" sobre una fila, abre el runner correcto:
//     TestRunnerDialog (mock) | TfRunnerDialog (tf) | EssayBrowserDialog
//     (essay – lista de preguntas con su respuesta modelo desplegable).
//
// La lista, el rename, el delete y el popmenu son comunes a los 3 kinds.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_dialog.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/features/billing/application/plan_gates.dart';

import '../../application/subjects_providers.dart';
import '../../domain/subject.dart';
import 'runners/count_picker_dialog.dart';
import 'runners/show_test_modal.dart';
import 'runners/test_runner_dialog.dart';
import 'runners/tf_runner_dialog.dart';

class SavedTestsLibrary extends ConsumerStatefulWidget {
  const SavedTestsLibrary({
    required this.subjectId,
    this.kind = SavedTestKind.mock,
    super.key,
  });

  final String subjectId;
  final SavedTestKind kind;

  @override
  ConsumerState<SavedTestsLibrary> createState() => _SavedTestsLibraryState();
}

class _SavedTestsLibraryState extends ConsumerState<SavedTestsLibrary> {
  bool _busy = false;

  /// Tests extra cargados via "Ver mas" (paginacion local). Los primeros 50
  /// vienen del savedTestsProvider; cuando el usuario pulsa "Ver mas" se
  /// fetchea offset 50, 100, etc. y se acumulan aqui.
  final List<SavedTest> _extras = [];
  bool _loadingMore = false;
  bool _noMoreToLoad = false;

  SavedTestsQuery get _query =>
      (subjectId: widget.subjectId, kind: widget.kind);

  Future<void> _loadMore(int currentTotal) async {
    if (_loadingMore || _noMoreToLoad) return;
    setState(() => _loadingMore = true);
    try {
      final more = await ref.read(subjectsDataSourceProvider).listSavedTests(
            widget.subjectId,
            kind: widget.kind,
            offset: currentTotal,
          );
      if (!mounted) return;
      setState(() {
        _extras.addAll(more);
        if (more.length < 50) _noMoreToLoad = true;
      });
    } catch (_) {
      if (mounted) await showAppErrorDialog(context);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _runAll() async {
    if (_busy) return;
    // GATE plan Max: "Hacer test de todo el temario" requiere Max.
    if (!ref.read(isMaxPlanProvider)) {
      await showMaxOnlyDialog(context, source: 'my_material_${widget.kind.slug}_run_all');
      return;
    }
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ds = ref.read(subjectsDataSourceProvider);
      final List<String> ids;
      switch (widget.kind) {
        case SavedTestKind.mock:
          final bank = await ds.listExamQuestions(widget.subjectId);
          ids = bank.map((q) => q.id).toList(growable: false);
        case SavedTestKind.tf:
          final bank = await ds.listTfBank(widget.subjectId);
          ids = bank.map((q) => q.id).toList(growable: false);
        case SavedTestKind.essay:
          final bank = await ds.listEssayBank(widget.subjectId);
          ids = bank.map((q) => q.id).toList(growable: false);
      }
      if (ids.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
        return;
      }
      final d = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final date = '${two(d.day)}/${two(d.month)}/${d.year}';
      final saved = await ds.createSavedTest(
        subjectId: widget.subjectId,
        title: '${l.studyTestScopeAll} · $date · ${ids.length}',
        questionIds: ids,
        nodeIds: const [],
        kind: widget.kind,
      );
      ref.invalidate(savedTestsProvider(_query));
      if (!mounted) return;
      await _runSaved(saved);
    } catch (_) {
      if (mounted) await showAppErrorDialog(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSaved(SavedTest s) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ds = ref.read(subjectsDataSourceProvider);
    switch (widget.kind) {
      case SavedTestKind.mock:
        final qs = await ds.getSavedTestQuestions(s);
        if (!mounted) return;
        if (qs.isEmpty) {
          messenger.showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
          return;
        }
        final count = await showCountPickerDialog(context, available: qs.length);
        if (count == null || !mounted) return;
        final shuffled = List.of(qs)..shuffle();
        final take = count <= 0 || count >= shuffled.length ? shuffled.length : count;
        await showTestModal(
          context,
          TestRunnerDialog(
            subjectId: widget.subjectId,
            questions: shuffled.sublist(0, take),
            timed: false,
            minutes: 0,
            penalty: true,
            nodeIds: s.nodeIds,
            onSelectNode: (_) {},
            savedTestId: s.id,
          ),
        );
      case SavedTestKind.tf:
        final qs = await ds.getSavedTfTestQuestions(s);
        if (!mounted) return;
        if (qs.isEmpty) {
          messenger.showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
          return;
        }
        final count = await showCountPickerDialog(context, available: qs.length);
        if (count == null || !mounted) return;
        final shuffled = List.of(qs)..shuffle();
        final take = count <= 0 || count >= shuffled.length ? shuffled.length : count;
        await showTestModal(
          context,
          TfRunnerDialog(
            questions: shuffled.sublist(0, take),
            timed: false,
            minutes: 0,
            penalty: true,
          ),
        );
      case SavedTestKind.essay:
        final qs = await ds.getSavedEssayTestQuestions(s);
        if (!mounted) return;
        if (qs.isEmpty) {
          messenger.showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
          return;
        }
        // No hay runner cronometrado para ensayo: abrimos un modal con
        // tarjetas expandibles (pregunta + respuesta modelo desplegable).
        await showTestModal(
          context,
          EssayBrowserDialog(title: s.title, questions: qs),
        );
    }
  }

  Future<void> _rename(SavedTest s) async {
    final l = context.l10n;
    final controller = TextEditingController(text: s.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.studyTestSavedRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l.actionSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle == null || newTitle.isEmpty || newTitle == s.title) return;
    try {
      await ref
          .read(subjectsDataSourceProvider)
          .renameSavedTest(s.id, newTitle);
      ref.invalidate(savedTestsProvider(_query));
    } catch (_) {
      if (mounted) await showAppErrorDialog(context);
    }
  }

  Future<void> _delete(SavedTest s) async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.studyTestSavedDelete,
      body: l.studyTestSavedDeleteConfirm,
      confirmLabel: l.aiDeleteCta,
      danger: true,
    );
    if (ok != true) return;
    try {
      await ref.read(subjectsDataSourceProvider).deleteSavedTest(s.id);
      ref.invalidate(savedTestsProvider(_query));
    } catch (_) {
      if (mounted) await showAppErrorDialog(context);
    }
  }

  /// Cuenta de preguntas en el banco para el [kind] del widget (para el
  /// banner). Lee los providers de bank existentes.
  int _bankCount() {
    switch (widget.kind) {
      case SavedTestKind.mock:
        return ref
                .watch(examQuestionsProvider(widget.subjectId))
                .valueOrNull
                ?.length ??
            0;
      case SavedTestKind.tf:
        return ref
                .watch(tfQuestionsProvider(widget.subjectId))
                .valueOrNull
                ?.length ??
            0;
      case SavedTestKind.essay:
        return ref
                .watch(essayQuestionsProvider(widget.subjectId))
                .valueOrNull
                ?.length ??
            0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final total = _bankCount();
    final listAsync = ref.watch(savedTestsProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── Banner banco + botón "Hacer test de TODO" ─────────────
        PremiumCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: context.colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l.studyTestBankTotal(total),
                  style: context.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (total > 0)
                FilledButton.icon(
                  onPressed: _busy ? null : _runAll,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: Text(l.studyTestRunAll),
                ),
            ],
          ),
        ),
        AppSpacing.gapMd,
        // ─── Lista de tests guardados ──────────────────────────────
        PremiumCard(
          padding: EdgeInsets.zero,
          child: listAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: AppLoadingState()),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(l.errorGeneric),
            ),
            data: (tests) {
              if (tests.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AppEmptyState(
                    icon: Icons.quiz_outlined,
                    title: l.studyTestSavedListTitle,
                    message: l.studyTestSavedEmpty,
                  ),
                );
              }
              // Concatenamos la primera pagina (50 del provider) con los
              // extras cargados via "Ver mas". El boton solo aparece si la
              // primera pagina llego al limite (= probablemente hay mas).
              final all = [...tests, ..._extras];
              final mightHaveMore =
                  tests.length >= 50 && !_noMoreToLoad;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      l.studyTestSavedListTitle,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final t in all)
                    _SavedTestTile(
                      test: t,
                      onRun: () => _runSaved(t),
                      onRename: () => _rename(t),
                      onDelete: () => _delete(t),
                    ),
                  if (mightHaveMore)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Center(
                        child: _loadingMore
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : OutlinedButton.icon(
                                onPressed: () => _loadMore(all.length),
                                icon: const Icon(Icons.expand_more, size: 18),
                                label: Text(l.actionLoadMore),
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Una fila de la lista de saved_tests. Muestra titulo, fecha, count y la
/// nota mas reciente (si la hay).
class _SavedTestTile extends ConsumerWidget {
  const _SavedTestTile({
    required this.test,
    required this.onRun,
    required this.onRename,
    required this.onDelete,
  });

  final SavedTest test;
  final VoidCallback onRun;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = context.colors;
    final attemptsAsync = ref.watch(savedTestAttemptsProvider(test.id));
    final lastGrade = attemptsAsync.maybeWhen(
      data: (a) => a.isEmpty ? null : a.first.grade,
      orElse: () => null,
    );
    final attemptCount = attemptsAsync.maybeWhen(
      data: (a) => a.length,
      orElse: () => 0,
    );
    // Essay no tiene auto-corrección; ocultamos "ultima nota".
    final showGrade = test.kind != SavedTestKind.essay;
    return ListTile(
      title: Text(test.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l.studyTestSavedQuestionCount(test.questionCount)} · '
            '${_fmtDate(test.createdAt)}',
            style: context.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (showGrade && lastGrade != null)
            Text(
              l.studyTestSavedLastScore(lastGrade.toStringAsFixed(2)),
              style: context.textTheme.labelSmall?.copyWith(
                color: lastGrade >= 5 ? Colors.green.shade700 : scheme.error,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (showGrade)
            Text(
              l.studyTestSavedNeverTaken,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          if (showGrade && attemptCount > 1)
            Text(
              '×$attemptCount',
              style: context.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l.studyTestStart,
            icon: const Icon(Icons.play_arrow, size: 20),
            onPressed: onRun,
          ),
          PopupMenuButton<String>(
            tooltip: '',
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  onRename();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'rename',
                child: Row(children: [
                  const Icon(Icons.edit_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(l.studyTestSavedRename),
                ],),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 18, color: scheme.error),
                  const SizedBox(width: AppSpacing.sm),
                  Text(l.studyTestSavedDelete),
                ],),
              ),
            ],
          ),
        ],
      ),
      onTap: onRun,
    );
  }
}

/// Visor de un saved_test de tipo essay: lista de preguntas con respuesta
/// modelo desplegable. No tiene cronómetro ni auto-corrección.
class EssayBrowserDialog extends StatelessWidget {
  const EssayBrowserDialog({
    required this.title,
    required this.questions,
    super.key,
  });

  final String title;
  final List<EssayQuestion> questions;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                IconButton(
                  tooltip: l.actionClose,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: questions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (_, i) {
                  final q = questions[i];
                  return PremiumCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(top: AppSpacing.sm),
                      title: Text(
                        '${i + 1}. ${q.question}',
                        style: context.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            q.answer,
                            style: context.textTheme.bodyMedium
                                ?.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.actionClose),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
