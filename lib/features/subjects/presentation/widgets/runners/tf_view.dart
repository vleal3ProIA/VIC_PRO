// ============================================================================
// subjects · TfView — configurador del test Verdadero/Falso
// ----------------------------------------------------------------------------
// Vista de configuración que elige el ámbito (todo / secciones), el número de
// afirmaciones, el tiempo y la penalización, y abre el banco V/F en un
// [TfRunnerDialog]. También expone botones para Generar / Regenerar el banco
// vía `subjectsDataSourceProvider.generateTfBank`.
//
// Extraído de `subject_study_panel.dart` (antes `_TfView` privado).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_dialog.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../../application/subjects_providers.dart';
import '../../../data/subjects_datasource.dart';
import '../../../domain/subject.dart';
import 'count_picker_dialog.dart';
import 'index_tree_picker.dart';
import 'saved_test_picker_dialog.dart';
import 'show_test_modal.dart';
import 'tf_runner_dialog.dart';

/// Configurador del test V/F: secciones, nº afirmaciones, tiempo y penalización,
/// con Generar/Regenerar y Empezar (abre [TfRunnerDialog] vía [showTestModal]).
class TfView extends ConsumerStatefulWidget {
  const TfView({required this.subjectId, required this.nodes, super.key});

  final String subjectId;
  final List<IndexNode> nodes;

  @override
  ConsumerState<TfView> createState() => _TfViewState();
}

class _TfViewState extends ConsumerState<TfView> {
  bool _busy = false;

  // Configuración del test.
  // El selector de cantidad ya NO esta aqui: se elige al pulsar "Empezar"
  // mediante [showCountPickerDialog] (presets 10/25/50/75/100/TODAS) sobre
  // el banco real disponible.
  bool _all = true;
  final Set<String> _selected = {};
  bool _timed = false;
  int _minutes = 20;
  bool _penalty = true;

  /// Ids del ámbito elegido: si es "todo", todos los nodos; si no, las
  /// secciones marcadas MÁS sus descendientes (las afirmaciones se etiquetan
  /// al nodo hoja cuyo texto se usó).
  Set<String> _scopeNodeIds() {
    if (_all) return widget.nodes.map((n) => n.id).toSet();
    final byParent = <String?, List<IndexNode>>{};
    for (final n in widget.nodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    final out = <String>{};
    void add(String id) {
      if (!out.add(id)) return;
      for (final c in byParent[id] ?? const <IndexNode>[]) {
        add(c.id);
      }
    }
    for (final id in _selected) {
      add(id);
    }
    return out;
  }

  /// Afirmaciones del banco que caen dentro del ámbito elegido.
  List<TfQuestion> _pool(List<TfQuestion> bank) {
    if (_all) return bank;
    final scope = _scopeNodeIds();
    return bank
        .where((q) => q.nodeId != null && scope.contains(q.nodeId))
        .toList();
  }

  /// "Realizar test" V/F: abre picker de saved_tests kind=tf, multi-select →
  /// combinar y arrancar. Modal cantidad → TfRunnerDialog.
  Future<void> _open() async {
    final pick = await showSavedTestPicker(
      context,
      subjectId: widget.subjectId,
      kind: SavedTestKind.tf,
    );
    if (pick == null || !mounted) return;
    final l = context.l10n;
    final ds = ref.read(subjectsDataSourceProvider);
    SavedTest? saved;
    try {
      if (pick.isSingle) {
        saved = await ds.getSavedTest(pick.singleId!);
      } else if (pick.isCombine) {
        final newId = await ds.combineSavedTests(
          sourceIds: pick.combineIds,
          title: l.studyTestSavedCombineTitle(pick.combineIds.length, 0),
        );
        saved = await ds.getSavedTest(newId);
        if (saved != null) {
          final fixed = l.studyTestSavedCombineTitle(
            pick.combineIds.length,
            saved.questionCount,
          );
          await ds.renameSavedTest(saved.id, fixed);
        }
        ref.invalidate(savedTestsProvider(
          (subjectId: widget.subjectId, kind: SavedTestKind.tf),
        ),);
      }
    } catch (_) {
      if (mounted) await showAppErrorDialog(context);
      return;
    }
    if (saved == null || !mounted) return;
    final qs = await ds.getSavedTfTestQuestions(saved);
    if (qs.isEmpty || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
      }
      return;
    }
    final count =
        await showCountPickerDialog(context, available: qs.length);
    if (count == null || !mounted) return;
    final shuffled = List.of(qs)..shuffle();
    final take = count <= 0 || count >= shuffled.length ? shuffled.length : count;
    await showTestModal(
      context,
      TfRunnerDialog(
        questions: shuffled.sublist(0, take),
        timed: _timed,
        minutes: _minutes,
        penalty: _penalty,
      ),
    );
  }

  /// "Generar test" V/F: rellena el banco para la selección y crea un
  /// SavedTest kind=tf con todas las preguntas del ámbito.
  Future<void> _generate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ds = ref.read(subjectsDataSourceProvider);
      await ds.generateTfBank(
        subjectId: widget.subjectId,
        nodeIds: _all ? const [] : _scopeNodeIds().toList(),
      );
      ref.invalidate(tfQuestionsProvider(widget.subjectId));
      final bank = await ds.listTfBank(widget.subjectId);
      final pool = _pool(bank);
      if (pool.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
        }
        return;
      }
      final qIds = pool.map((q) => q.id).toList(growable: false);
      final nIds = _all
          ? widget.nodes.map((n) => n.id).toList()
          : _scopeNodeIds().toList();
      final title = _autoTitle(nIds, qIds.length);
      final saved = await ds.createSavedTest(
        subjectId: widget.subjectId,
        title: title,
        questionIds: qIds,
        nodeIds: nIds,
        kind: SavedTestKind.tf,
      );
      ref.invalidate(savedTestsProvider(
        (subjectId: widget.subjectId, kind: SavedTestKind.tf),
      ),);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(l.studyTestSavedCreated(saved.title, qIds.length)),
          ),
        );
      }
    } on SubjectsException catch (_) {
      if (mounted) await showAppErrorDialog(context);
    } catch (_) {
      if (mounted) await showAppErrorDialog(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _autoTitle(List<String> nodeIds, int qCount) {
    final l = context.l10n;
    final allNodes = {for (final n in widget.nodes) n.id: n};
    final picked =
        nodeIds.map((id) => allNodes[id]).whereType<IndexNode>().toList();
    final tops = picked.where((n) => n.depth == 1).toList();
    String scope;
    if (_all || tops.isEmpty && picked.length == widget.nodes.length) {
      scope = l.studyTestScopeAll;
    } else if (tops.isNotEmpty) {
      final names = tops.take(2).map((n) => n.title).join(' + ');
      scope = tops.length > 2 ? '$names + ${tops.length - 2}' : names;
    } else {
      final first = picked.first;
      scope =
          picked.length > 1 ? '${first.title} + ${picked.length - 1}' : first.title;
    }
    return '$scope · $qCount';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_busy) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.sm),
            Text(l.studyGenerating, style: context.textTheme.bodySmall),
          ],
        ),
      );
    }
    return _config(context);
  }

  Widget _config(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final bank =
        ref.watch(tfQuestionsProvider(widget.subjectId)).valueOrNull ??
            const <TfQuestion>[];
    final canGenerate = _all || _selected.isNotEmpty;
    final pool = _pool(bank);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // ─── Secciones ───
        Row(
          children: [
            Expanded(
              child: Text(
                l.studyTestSections,
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(l.studyTestAll, style: context.textTheme.bodySmall),
            Switch(value: _all, onChanged: (v) => setState(() => _all = v)),
          ],
        ),
        if (!_all)
          IndexTreePicker(
            nodes: widget.nodes,
            selected: _selected,
            onSelectionChanged: (next) => setState(() {
              _selected
                ..clear()
                ..addAll(next);
            }),
          ),
        const Divider(height: AppSpacing.lg),
        // El selector "Nº de afirmaciones" se elige al pulsar "Empezar"
        // (showCountPickerDialog). En este config solo quedan opciones
        // que afectan al test en si (tiempo, penalizacion).
        // ─── Tiempo ───
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.studyTestTimed),
          value: _timed,
          onChanged: (v) => setState(() => _timed = v),
        ),
        if (_timed)
          Row(
            children: [
              Expanded(child: Text(l.studyTestMinutes)),
              DropdownButton<int>(
                value: _minutes,
                items: [5, 10, 20, 30, 45, 60]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) => setState(() => _minutes = v ?? 20),
              ),
            ],
          ),
        // ─── Penalización ───
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.studyTestPenalty),
          value: _penalty,
          onChanged: (v) => setState(() => _penalty = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (pool.isNotEmpty)
          Text(
            l.studyTestBank(pool.length),
            style: context.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            // 1) Generar test V/F: rellena el banco + crea saved_test kind=tf.
            PremiumButton(
              label: l.studyTestGenerate,
              leadingIcon: Icons.auto_awesome_outlined,
              onPressed: canGenerate ? _generate : null,
            ),
            // 2) Realizar test: picker de saved_tests del temario (kind=tf).
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: Text(l.studyTestStart),
            ),
            // 3) Ver mis tests V/F: biblioteca en /mis-temarios/<id>/tf.
            OutlinedButton.icon(
              onPressed: () => context.goNamed(
                RouteNames.myMaterialSubjectKind,
                pathParameters: {'id': widget.subjectId, 'kind': 'tf'},
              ),
              icon: const Icon(Icons.history, size: 16),
              label: Text(l.studyTestViewHistory),
            ),
          ],
        ),
      ],
    );
  }
}
