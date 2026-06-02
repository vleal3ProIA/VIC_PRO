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

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_dialog.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../../application/subjects_providers.dart';
import '../../../data/subjects_datasource.dart';
import '../../../domain/subject.dart';
import 'count_picker_dialog.dart';
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

  Future<void> _open(List<TfQuestion> pool) async {
    if (pool.isEmpty) return;
    final count =
        await showCountPickerDialog(context, available: pool.length);
    if (count == null) return; // cancelado
    if (!mounted) return;
    final qs = List.of(pool)..shuffle();
    final take = count <= 0 || count >= qs.length ? qs.length : count;
    await showTestModal(
      context,
      TfRunnerDialog(
        questions: qs.sublist(0, take),
        timed: _timed,
        minutes: _minutes,
        penalty: _penalty,
      ),
    );
  }

  Future<void> _generate({bool force = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref.read(subjectsDataSourceProvider).generateTfBank(
            subjectId: widget.subjectId,
            nodeIds: _all ? const [] : _scopeNodeIds().toList(),
            force: force,
          );
      ref.invalidate(tfQuestionsProvider(widget.subjectId));
      if (mounted) {
        final msg = r.pending > 0
            ? '${l.studyBankProgress(r.total, r.generated)} · '
                '${l.studyBankPending(r.pending)}'
            : l.studyBankProgress(r.total, r.generated);
        messenger.showSnackBar(
          SnackBar(duration: const Duration(seconds: 6), content: Text(msg)),
        );
      }
    } on SubjectsException catch (_) {
      // PR 0083: modal central en lugar de snackbar para errores genericos.
      // El detalle tecnico esta ya en `error_reports` (admin /admin/errors).
      if (mounted) {
        await showAppErrorDialog(context);
      }
    } catch (_) {
      if (mounted) {
        await showAppErrorDialog(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final sections = widget.nodes.where((n) => n.parentId != null).toList();
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
          for (final s in sections)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 4 + s.depth * 12.0),
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(s.id),
              title:
                  Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selected.add(s.id);
                } else {
                  _selected.remove(s.id);
                }
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
            if (pool.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _open(pool),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(l.studyTestStart),
              ),
            PremiumButton(
              label: l.studyTestGenerate,
              leadingIcon: Icons.auto_awesome_outlined,
              onPressed: canGenerate ? _generate : null,
            ),
            if (pool.isNotEmpty)
              OutlinedButton.icon(
                onPressed: canGenerate ? () => _generate(force: true) : null,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(l.studyTestRegenerate),
              ),
          ],
        ),
      ],
    );
  }
}
