// ============================================================================
// subjects · SavedTestsLibrary
// ----------------------------------------------------------------------------
// Vista de "biblioteca de tests guardados" para `/mis-temarios/<id>/mock`:
//   - Banner con el total de preguntas en el banco + boton "Hacer test de
//     TODAS las preguntas" (genera un saved_test con todas y arranca).
//   - Lista de saved_tests del temario: titulo, fecha, count, ultima nota.
//     Tap en uno → arranca el runner (modal cantidad → preguntas → resultados).
//   - Menu por test: renombrar, borrar.
//   - Acciones extra cuando hay attempts del test: ver historial (gráfica
//     simple text-based para ahora; futura mejora visual).
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

import '../../application/subjects_providers.dart';
import '../../domain/subject.dart';
import 'runners/count_picker_dialog.dart';
import 'runners/show_test_modal.dart';
import 'runners/test_runner_dialog.dart';

class SavedTestsLibrary extends ConsumerStatefulWidget {
  const SavedTestsLibrary({required this.subjectId, super.key});
  final String subjectId;

  @override
  ConsumerState<SavedTestsLibrary> createState() => _SavedTestsLibraryState();
}

class _SavedTestsLibraryState extends ConsumerState<SavedTestsLibrary> {
  bool _busy = false;

  Future<void> _runAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ds = ref.read(subjectsDataSourceProvider);
      final bank = await ds.listExamQuestions(widget.subjectId);
      if (bank.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
        return;
      }
      final saved = await ds.createSavedTest(
        subjectId: widget.subjectId,
        title: '${l.studyTestScopeAll} · ${bank.length}',
        questionIds: bank.map((q) => q.id).toList(),
        nodeIds: const [],
      );
      ref.invalidate(savedTestsProvider(widget.subjectId));
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
    final questions = await ds.getSavedTestQuestions(s);
    if (!mounted) return;
    if (questions.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
      return;
    }
    final count = await showCountPickerDialog(context, available: questions.length);
    if (count == null || !mounted) return;
    final qs = List.of(questions)..shuffle();
    final take = count <= 0 || count >= qs.length ? qs.length : count;
    await showTestModal(
      context,
      TestRunnerDialog(
        subjectId: widget.subjectId,
        questions: qs.sublist(0, take),
        timed: false,
        minutes: 0,
        penalty: true,
        nodeIds: s.nodeIds,
        onSelectNode: (_) {},
        savedTestId: s.id,
      ),
    );
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
      ref.invalidate(savedTestsProvider(widget.subjectId));
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
      ref.invalidate(savedTestsProvider(widget.subjectId));
    } catch (_) {
      if (mounted) await showAppErrorDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final bankAsync = ref.watch(examQuestionsProvider(widget.subjectId));
    final listAsync = ref.watch(savedTestsProvider(widget.subjectId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── Banner banco + botón "Hacer test de TODO" ─────────────
        PremiumCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: bankAsync.when(
            loading: () => const Center(child: AppLoadingState()),
            error: (_, __) => Text(l.errorGeneric),
            data: (bank) => Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: context.colors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l.studyTestBankTotal(bank.length),
                    style: context.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (bank.isNotEmpty)
                  FilledButton.icon(
                    onPressed: _busy ? null : _runAll,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(l.studyTestRunAll),
                  ),
              ],
            ),
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
                  for (final t in tests) _SavedTestTile(
                    test: t,
                    onRun: () => _runSaved(t),
                    onRename: () => _rename(t),
                    onDelete: () => _delete(t),
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
/// nota mas reciente (resuelta via `savedTestAttemptsProvider`). Click =
/// arrancar; menu = renombrar / borrar.
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
          if (lastGrade != null)
            Text(
              l.studyTestSavedLastScore(lastGrade.toStringAsFixed(2)),
              style: context.textTheme.labelSmall?.copyWith(
                color: lastGrade >= 5
                    ? Colors.green.shade700
                    : scheme.error,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Text(
              l.studyTestSavedNeverTaken,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          if (attemptCount > 1)
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
