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
import 'package:myapp/core/widgets/app_error_dialog.dart'
    show showAiQuotaExceededSnackBar, showAppErrorDialog;
import 'package:myapp/core/widgets/premium/premium.dart';
import '../../../application/subjects_providers.dart';
import '../../../data/subjects_datasource.dart';
import '../../../domain/subject.dart';
import 'count_picker_dialog.dart';
import 'index_leaf_picker.dart';
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

  // Configuración del test V/F: el usuario elige UNA seccion HOJA del
  // indice; no hay toggle "Todo el temario" (filosofia "punto por punto").
  String? _selectedNodeId;
  bool _timed = false;
  int _minutes = 20;
  bool _penalty = true;

  /// Afirmaciones del banco que pertenecen al nodo hoja seleccionado.
  List<TfQuestion> _pool(List<TfQuestion> bank) {
    final id = _selectedNodeId;
    if (id == null) return const [];
    return bank.where((q) => q.nodeId == id).toList();
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

  /// "Generar test" V/F: genera afirmaciones de la seccion elegida y crea
  /// un SavedTest kind=tf con esas preguntas. Solo activo cuando hay una
  /// hoja seleccionada — no hay opcion de "Todo el temario".
  Future<void> _generate() async {
    if (_busy) return;
    final nodeId = _selectedNodeId;
    if (nodeId == null) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ds = ref.read(subjectsDataSourceProvider);
      await ds.generateTfBank(
        subjectId: widget.subjectId,
        nodeIds: [nodeId],
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
      final nIds = [nodeId];
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
    } on AiQuotaExceededException catch (q) {
      if (mounted) showAiQuotaExceededSnackBar(context, q.dailyLimit);
    } on SubjectsException catch (_) {
      if (mounted) await showAppErrorDialog(context);
    } catch (_) {
      if (mounted) await showAppErrorDialog(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _autoTitle(List<String> nodeIds, int qCount) {
    final allNodes = {for (final n in widget.nodes) n.id: n};
    final first = nodeIds.isEmpty ? null : allNodes[nodeIds.first];
    final scope = first?.title ?? '';
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${two(d.day)}/${two(d.month)}/${d.year}';
    return '$scope · $date · $qCount';
  }

  /// Breadcrumb de la seleccion (TITULO › CAPITULO › Articulo X).
  String? _breadcrumb() {
    final id = _selectedNodeId;
    if (id == null) return null;
    final byId = {for (final n in widget.nodes) n.id: n};
    final parts = <String>[];
    var cur = byId[id];
    while (cur != null) {
      parts.insert(0, cur.title);
      cur = cur.parentId == null ? null : byId[cur.parentId];
    }
    return parts.join(' › ');
  }

  @override
  Widget build(BuildContext context) {
    // Loading non-blocking: el _busy se renderiza dentro de _config como un
    // LinearProgressIndicator arriba, sin esconder el indice.
    return _config(context);
  }

  Widget _config(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final bank =
        ref.watch(tfQuestionsProvider(widget.subjectId)).valueOrNull ??
            const <TfQuestion>[];
    final canGenerate = _selectedNodeId != null && !_busy;
    final pool = _pool(bank);
    final crumb = _breadcrumb();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.studyGenerating,
            style: context.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        // ─── Secciones ───
        // Solo seleccion unica de hoja del indice. Sin toggle "Todo".
        Text(
          l.studyTestSections,
          style: context.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (crumb != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              crumb,
              style: context.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        IndexLeafPicker(
          nodes: widget.nodes,
          selectedNodeId: _selectedNodeId,
          onChanged: (v) => setState(() => _selectedNodeId = v),
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
