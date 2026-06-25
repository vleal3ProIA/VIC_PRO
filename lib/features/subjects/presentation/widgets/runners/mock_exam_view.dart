// ============================================================================
// subjects · MockExamView — configurador del simulacro / test cronometrado
// ----------------------------------------------------------------------------
// Vista de configuración que elige el ámbito (todo / secciones), el número de
// preguntas, el tiempo y la penalización, y abre el banco de preguntas en un
// [TestRunnerDialog]. También expone botones para Generar / Regenerar el banco
// vía `subjectsDataSourceProvider.generateExam`.
//
// Extraído de `subject_study_panel.dart` (antes `_MockExamView` privado).
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
import 'test_runner_dialog.dart';

/// Configurador del simulacro: secciones, nº preguntas, tiempo y penalización,
/// con Generar/Regenerar y Empezar (abre [TestRunnerDialog] vía
/// [showTestModal]).
class MockExamView extends ConsumerStatefulWidget {
  const MockExamView({
    required this.subjectId,
    required this.nodes,
    required this.onSelectNode,
    super.key,
  });

  final String subjectId;
  final List<IndexNode> nodes;
  final ValueChanged<String> onSelectNode;

  @override
  ConsumerState<MockExamView> createState() => _MockExamViewState();
}

class _MockExamViewState extends ConsumerState<MockExamView> {
  bool _busy = false;

  // Configuración del test.
  // El usuario elige UNA seccion HOJA del indice via IndexLeafPicker. NO
  // hay toggle "Todo el temario" — la generacion masiva (plan Max) se hace
  // desde /mis-temarios. Esto fuerza al usuario a estudiar punto por punto.
  String? _selectedNodeId;
  bool _timed = false;
  int _minutes = 20;
  bool _penalty = true;

  /// Preguntas del banco que pertenecen al nodo hoja seleccionado. Si no
  /// hay seleccion, devuelve lista vacia (no se puede generar ni realizar).
  List<QuizQuestion> _pool(List<QuizQuestion> bank) {
    final id = _selectedNodeId;
    if (id == null) return const [];
    return bank.where((q) => q.nodeId == id).toList();
  }

  /// Abre el flujo "Realizar test":
  ///   1) Picker con la lista de saved_tests del temario (multi-select).
  ///   2) Si elige UNO  → carga sus preguntas y arranca.
  ///   3) Si combina N  → RPC combine_saved_tests → carga las del combinado.
  ///   4) Modal cantidad 10/25/50/75/100/TODAS → runner.
  Future<void> _open() async {
    final pick = await showSavedTestPicker(
      context,
      subjectId: widget.subjectId,
      kind: SavedTestKind.mock,
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
        // El título real necesita el qcount ya conocido tras leer el saved.
        if (saved != null) {
          final fixed = l.studyTestSavedCombineTitle(
            pick.combineIds.length,
            saved.questionCount,
          );
          await ds.renameSavedTest(saved.id, fixed);
          saved = SavedTest(
            id: saved.id,
            subjectId: saved.subjectId,
            title: fixed,
            kind: saved.kind,
            questionIds: saved.questionIds,
            nodeIds: saved.nodeIds,
            questionCount: saved.questionCount,
            createdAt: saved.createdAt,
            updatedAt: DateTime.now(),
          );
        }
        ref.invalidate(savedTestsProvider((subjectId: widget.subjectId, kind: SavedTestKind.mock)));
      }
    } catch (_) {
      if (mounted) await showAppErrorDialog(context);
      return;
    }
    if (saved == null || !mounted) return;

    final questions = await ds.getSavedTestQuestions(saved);
    if (questions.isEmpty || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
      }
      return;
    }
    final count = await showCountPickerDialog(
      context,
      available: questions.length,
    );
    if (count == null || !mounted) return;
    final qs = List.of(questions)..shuffle();
    final take = count <= 0 || count >= qs.length ? qs.length : count;
    await showTestModal(
      context,
      TestRunnerDialog(
        subjectId: widget.subjectId,
        questions: qs.sublist(0, take),
        timed: _timed,
        minutes: _minutes,
        penalty: _penalty,
        nodeIds: saved.nodeIds,
        onSelectNode: widget.onSelectNode,
        savedTestId: saved.id,
      ),
    );
  }

  /// Construye/extiende el banco para la selección actual (sin gastar IA
  /// cuando ya está cubierto) y, tras refrescar, crea un [SavedTest]
  /// plantilla con TODAS las preguntas del ámbito y un título auto-descriptivo. Ese
  /// test queda en `Mi Material → Tests` listo para realizarse las veces
  /// que el usuario quiera.
  Future<void> _generate() async {
    if (_busy) return;
    final nodeId = _selectedNodeId;
    // En este configurador solo se genera de UNA seccion hoja. Si el usuario
    // quiere generar de TODO el temario, lo hace desde /mis-temarios (gated
    // por plan Max). Aqui simplemente no hay opcion.
    if (nodeId == null) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ds = ref.read(subjectsDataSourceProvider);
      // 1) Rellenar banco solo de la seccion elegida.
      await ds.generateExam(
        subjectId: widget.subjectId,
        nodeIds: [nodeId],
      );
      // 2) Releer banco actualizado y filtrar por nodo.
      ref.invalidate(examQuestionsProvider(widget.subjectId));
      final bank = await ds.listExamQuestions(widget.subjectId);
      final pool = _pool(bank);
      if (pool.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(content: Text(l.studyTestNoBank)));
        }
        return;
      }
      // 3) Crear saved_test con las preguntas de esa seccion.
      final qIds = pool.map((q) => q.id).toList(growable: false);
      final nIds = [nodeId];
      final title = _autoTitle(nIds, qIds.length);
      final saved = await ds.createSavedTest(
        subjectId: widget.subjectId,
        title: title,
        questionIds: qIds,
        nodeIds: nIds,
      );
      ref.invalidate(savedTestsProvider((subjectId: widget.subjectId, kind: SavedTestKind.mock)));
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

  /// Construye un título descriptivo a partir del nodo elegido + fecha actual,
  /// para que tests del mismo articulo en distintos dias no salgan iguales.
  /// Ejemplo: "Artículo 14 · 12/03/2026 · 24".
  String _autoTitle(List<String> nodeIds, int qCount) {
    final allNodes = {for (final n in widget.nodes) n.id: n};
    final first = nodeIds.isEmpty ? null : allNodes[nodeIds.first];
    final scope = first?.title ?? '';
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${two(d.day)}/${two(d.month)}/${d.year}';
    return '$scope · $date · $qCount';
  }

  /// Breadcrumb desde el nodo padre raiz hasta el nodo elegido. Ejemplo:
  /// "TÍTULO I › CAPÍTULO II › Sección 1ª › Artículo 14". Null si no hay
  /// nodo seleccionado.
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
    // Loading non-blocking: NO reemplazamos toda la vista cuando _busy=true.
    // El usuario mantiene el contexto (su seleccion del indice + opciones).
    // El LinearProgressIndicator dentro del config le da feedback visual
    // sin esconder la pantalla.
    return _config(context);
  }

  Widget _config(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final bank =
        ref.watch(examQuestionsProvider(widget.subjectId)).valueOrNull ??
            const <QuizQuestion>[];
    final canGenerate = _selectedNodeId != null && !_busy;
    final pool = _pool(bank);
    final crumb = _breadcrumb();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // Loading non-blocking: barra delgada arriba cuando se esta generando
        // o consultando el banco, sin esconder la seleccion del indice.
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
        // Sin toggle "Todo el temario": el usuario solo puede elegir UNA
        // seccion hoja del indice. Para generar masivo de TODO existe la
        // pagina /mis-temarios (gated por plan Max).
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
        // El selector "Nº de preguntas" se elige al pulsar "Empezar"
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
            // 1) Generar test: rellena lo que falte en el banco (no regenera
            //    lo ya existente; sin gasto de IA si todo esta cubierto).
            PremiumButton(
              label: l.studyTestGenerate,
              leadingIcon: Icons.auto_awesome_outlined,
              onPressed: canGenerate ? _generate : null,
            ),
            // 2) Realizar test: abre picker con la lista de saved_tests
            //    del temario (multi-select → combinar).
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: Text(l.studyTestStart),
            ),
            // 3) Ver mis tests: navega al historial dentro de /mis-temarios.
            OutlinedButton.icon(
              onPressed: () => context.goNamed(
                RouteNames.myMaterialSubjectKind,
                pathParameters: {'id': widget.subjectId, 'kind': 'mock'},
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
