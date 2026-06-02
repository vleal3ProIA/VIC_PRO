// ============================================================================
// subjects · TfRunnerDialog — runner Verdadero/Falso
// ----------------------------------------------------------------------------
// Runner del test Verdadero/Falso. Clon de [TestRunnerDialog] adaptado a
// preguntas binarias (dos botones grandes en vez de A/B/C/D). NO se persiste
// en `exam_attempts` — el banco V/F es ephemeral en este sprint; el historial
// podrá añadirse más adelante si hace falta.
//
// Extraído de `subject_study_panel.dart` (antes `_TfRunnerDialog` privado).
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/markdown_text.dart';

import '../../../application/subjects_providers.dart';
import '../../../domain/subject.dart';

/// Diálogo full-screen que ejecuta un test Verdadero/Falso.
class TfRunnerDialog extends ConsumerStatefulWidget {
  const TfRunnerDialog({
    required this.questions,
    required this.timed,
    required this.minutes,
    required this.penalty,
    super.key,
  });

  final List<TfQuestion> questions;
  final bool timed;
  final int minutes;
  final bool penalty;

  @override
  ConsumerState<TfRunnerDialog> createState() => _TfRunnerDialogState();
}

class _TfRunnerDialogState extends ConsumerState<TfRunnerDialog> {
  late List<bool?> _answers;
  int _cur = 0;
  int _elapsed = 0;
  Timer? _timer;
  bool _done = false;
  bool _review = false;
  int _reviewCur = 0;

  /// Indices de las preguntas (en review) cuyo bloque "Ver en temario"
  /// esta desplegado mostrando original + explicado de su seccion.
  final Set<int> _expanded = <int>{};

  int get _totalSecs => widget.minutes * 60;
  int get _answered => _answers.where((a) => a != null).length;

  @override
  void initState() {
    super.initState();
    _answers = List<bool?>.filled(widget.questions.length, null);
    if (widget.timed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          _timer?.cancel();
          return;
        }
        setState(() => _elapsed++);
        if (_elapsed >= _totalSecs) _finish(confirm: false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  ({int correct, int wrong, int blank, double grade}) _score() {
    final total = widget.questions.length;
    var correct = 0;
    var wrong = 0;
    var blank = 0;
    for (var i = 0; i < total; i++) {
      final a = _answers[i];
      if (a == null) {
        blank++;
      } else if (a == widget.questions[i].isTrue) {
        correct++;
      } else {
        wrong++;
      }
    }
    final raw = widget.penalty ? correct - wrong.toDouble() : correct.toDouble();
    final grade = total == 0 ? 0.0 : (raw < 0 ? 0.0 : raw / total * 10);
    return (correct: correct, wrong: wrong, blank: blank, grade: grade);
  }

  Future<void> _finish({bool confirm = true}) async {
    if (confirm) {
      final l = context.l10n;
      final ok = await AppConfirmDialog.show(
        context,
        title: l.studyTestFinishTitle,
        body: l.studyTestFinishBody(_answered, widget.questions.length),
        confirmLabel: l.studyMockFinish,
      );
      if (ok != true) return;
    }
    _timer?.cancel();
    // Marcar el día estudiado (best-effort); no registramos en exam_attempts
    // porque el historial de V/F no está en el schema en este sprint.
    unawaited(ref.read(subjectsDataSourceProvider).recordStudyToday());
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = (size.width - 48).clamp(280.0, 1100.0);
    final h = size.height - 48;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: w,
        height: h,
        child: _done
            ? (_review ? _reviewPaged(context) : _results(context))
            : _running(context),
      ),
    );
  }

  Widget _header(BuildContext context, {required Widget trailing}) {
    final scheme = context.colors;
    final l = context.l10n;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.rule, size: 18, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              l.studioTf,
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _running(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final q = widget.questions[_cur];
    final total = widget.questions.length;
    final remaining = (_totalSecs - _elapsed).clamp(0, _totalSecs);
    final last = _cur == total - 1;
    final danger = widget.timed && remaining <= 30;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.timed) ...[
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: danger ? scheme.error : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _fmt(remaining),
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: danger ? scheme.error : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              FilledButton.icon(
                onPressed: _finish,
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: Text(l.studyMockFinish),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Afirmación sobre fondo azul claro, con su número (1/50).
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_cur + 1}/$total',
                              style: context.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            q.statement,
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Dos botones grandes: Verdadero / Falso.
                    Row(
                      children: [
                        Expanded(
                          child: _tfChoice(
                            context,
                            label: l.studyTfAnswerTrue,
                            icon: Icons.check,
                            color: Colors.green,
                            selected: _answers[_cur] ?? false,
                            onTap: () => setState(() {
                              final wasTrue = _answers[_cur] ?? false;
                              _answers[_cur] = wasTrue ? null : true;
                            }),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _tfChoice(
                            context,
                            label: l.studyTfAnswerFalse,
                            icon: Icons.close,
                            color: scheme.error,
                            selected: !(_answers[_cur] ?? true),
                            onTap: () => setState(() {
                              final wasFalse = !(_answers[_cur] ?? true);
                              _answers[_cur] = wasFalse ? null : false;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: _cur > 0 ? () => setState(() => _cur--) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              const Spacer(),
              Text(
                '${_cur + 1}/$total · $_answered',
                style: context.textTheme.titleSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: !last ? () => setState(() => _cur++) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _results(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final total = widget.questions.length;
    final s = _score();
    final correct = s.correct;
    final wrong = s.wrong;
    final blank = s.blank;
    final grade = s.grade;
    final gradeColor = grade >= 5 ? Colors.green.shade600 : scheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context,
          trailing: IconButton(
            tooltip: l.actionClose,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    children: [
                      Text(
                        l.studioQuizResult,
                        style: context.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${grade.toStringAsFixed(2)} / 10',
                        style: context.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: gradeColor,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l.studyTestAnswered(total - blank, total),
                        style: context.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        alignment: WrapAlignment.center,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.check,
                                size: 14, color: Colors.green,),
                            label: Text('${l.studyMockCorrect}: $correct'),
                          ),
                          Chip(
                            avatar: Icon(Icons.close,
                                size: 14, color: scheme.error,),
                            label: Text('${l.studyMockWrong}: $wrong'),
                          ),
                          Chip(
                            avatar: const Icon(Icons.remove, size: 14),
                            label: Text('${l.studyMockBlank}: $blank'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _review = true;
                              _reviewCur = 0;
                            }),
                            icon: const Icon(Icons.fact_check_outlined,
                                size: 16,),
                            label: Text(l.studyMockReview),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, size: 16),
                            label: Text(l.actionClose),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Repaso PAGINADO: una afirmación a la vez con Anterior/Siguiente y un
  /// botón de Finalizar siempre visible para salir.
  Widget _reviewPaged(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final total = widget.questions.length;
    final last = _reviewCur >= total - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context,
          trailing: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.flag_outlined, size: 16),
            label: Text(l.studyMockFinish),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _reviewItem(context, _reviewCur),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: _reviewCur > 0
                    ? () => setState(() => _reviewCur--)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              const Spacer(),
              Text(
                '${_reviewCur + 1}/$total',
                style: context.textTheme.titleSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: !last ? () => setState(() => _reviewCur++) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewItem(BuildContext context, int i) {
    final l = context.l10n;
    final scheme = context.colors;
    final q = widget.questions[i];
    final mine = _answers[i];
    final correctLabel =
        q.isTrue ? l.studyTfAnswerTrue : l.studyTfAnswerFalse;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${i + 1}. ${q.statement}',
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _tfChoice(
                  context,
                  label: l.studyTfAnswerTrue,
                  icon: Icons.check,
                  color: Colors.green,
                  selected: mine ?? false,
                  readOnly: true,
                  correct: q.isTrue,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _tfChoice(
                  context,
                  label: l.studyTfAnswerFalse,
                  icon: Icons.close,
                  color: scheme.error,
                  selected: !(mine ?? true),
                  readOnly: true,
                  correct: !q.isTrue,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Linea "Correcta: X" + boton "Ver en temario" cuando la pregunta
          // tiene nodo enlazado (q.nodeId != null). Al desplegar muestra el
          // texto original + el explicado IA de esa seccion.
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l.studyMockCorrect}: $correctLabel',
                  style: context.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (q.nodeId != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l.studyTestViewInMaterial,
                  icon: Icon(
                    _expanded.contains(i)
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: Colors.green.shade700,
                  ),
                  onPressed: () => setState(() {
                    if (_expanded.contains(i)) {
                      _expanded.remove(i);
                    } else {
                      _expanded.add(i);
                    }
                  }),
                ),
            ],
          ),
          if (q.explanation?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  q.explanation!,
                  style: context.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ),
            ),
          if (_expanded.contains(i) && q.nodeId != null)
            _reviewDetail(context, q.nodeId!),
        ],
      ),
    );
  }

  /// Panel desplegable bajo una pregunta en revision: muestra el ORIGINAL del
  /// temario + el EXPLICADO de la IA de la seccion enlazada (`nodeId`).
  /// Sigue el mismo patron que `TestRunnerDialog._reviewDetail`.
  Widget _reviewDetail(BuildContext context, String nodeId) {
    final l = context.l10n;
    final scheme = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailBlock(context, nodeId, 'original', l.studyTabOriginal),
          _detailBlock(context, nodeId, 'explained', l.studyTabExplained),
        ],
      ),
    );
  }

  /// Un bloque (Original o Explicado) del contenido de la seccion, leido
  /// del provider de contenido de nodos. Se omite si esta vacio.
  Widget _detailBlock(
    BuildContext context,
    String nodeId,
    String kind,
    String label,
  ) {
    final scheme = context.colors;
    final async = ref.watch(
      nodeContentProvider((nodeId: nodeId, kind: kind)),
    );
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (content) {
        if (content == null || content.trim().isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: context.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              MarkdownText(content),
            ],
          ),
        );
      },
    );
  }

  /// Tarjeta-botón con texto + icono. En modo runner es seleccionable; en modo
  /// review marca el correcto en verde y el fallo en rojo si lo hubo.
  Widget _tfChoice(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    bool readOnly = false,
    bool? correct,
    VoidCallback? onTap,
  }) {
    final scheme = context.colors;
    Color border = scheme.outlineVariant;
    Color fg = scheme.onSurface;
    Color? bg;
    var strong = false;
    if (readOnly) {
      if (correct ?? false) {
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.12);
        fg = Colors.green.shade800;
        strong = true;
      } else if (selected) {
        border = scheme.error;
        bg = scheme.error.withValues(alpha: 0.10);
        fg = scheme.error;
        strong = true;
      }
    } else if (selected) {
      border = color;
      bg = color.withValues(alpha: 0.12);
      fg = color;
      strong = true;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: strong ? 1.6 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: context.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
