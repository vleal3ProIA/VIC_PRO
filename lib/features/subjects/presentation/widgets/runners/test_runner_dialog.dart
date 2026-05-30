// ============================================================================
// subjects · TestRunnerDialog — runner de cuestionario (A/B/C/D)
// ----------------------------------------------------------------------------
// Test en marcha dentro de un modal casi a pantalla completa: la pregunta va
// sobre fondo azul claro con su número (1/50), las respuestas A/B/C/D en
// tarjetas, navegación adelante/atrás, "Finalizar" siempre visible (con
// confirmación) y, sin cerrar el modal, los resultados (nota /10 + desglose)
// y el repaso pregunta a pregunta (respuesta correcta + explicación + salto al
// temario). También sirve para revisar un intento pasado del historial
// ([startInReview] + [initialAnswers], sin volver a registrarlo).
//
// Extraído de `subject_study_panel.dart` (antes `_TestRunnerDialog` privado)
// para que /mis-temarios/<id>/<kind> pueda usarlo directamente sin pasar por
// el Panel. La lógica y la UI son idénticas al original.
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

/// Diálogo full-screen que ejecuta un test de opción múltiple.
class TestRunnerDialog extends ConsumerStatefulWidget {
  const TestRunnerDialog({
    required this.subjectId,
    required this.questions,
    required this.timed,
    required this.minutes,
    required this.penalty,
    required this.onSelectNode,
    this.nodeIds = const [],
    this.initialAnswers,
    this.startInReview = false,
    this.record = true,
    super.key,
  });

  final String subjectId;
  final List<QuizQuestion> questions;
  final bool timed;
  final int minutes;
  final bool penalty;
  final ValueChanged<String> onSelectNode;
  final List<String> nodeIds;
  final List<int?>? initialAnswers;
  final bool startInReview;
  final bool record;

  @override
  ConsumerState<TestRunnerDialog> createState() => _TestRunnerDialogState();
}

class _TestRunnerDialogState extends ConsumerState<TestRunnerDialog> {
  late List<int?> _answers;
  int _cur = 0;
  int _elapsed = 0;
  Timer? _timer;
  bool _done = false;
  bool _review = false;
  int _reviewCur = 0;
  final Set<int> _expanded = {};

  int get _totalSecs => widget.minutes * 60;
  int get _answered => _answers.where((a) => a != null).length;

  @override
  void initState() {
    super.initState();
    final init = widget.initialAnswers;
    _answers = (init != null && init.length == widget.questions.length)
        ? List<int?>.of(init)
        : List<int?>.filled(widget.questions.length, null);
    if (widget.startInReview) {
      _done = true;
      _review = true;
    } else if (widget.timed) {
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

  /// Calcula aciertos/fallos/en blanco y la nota /10 (con o sin penalización).
  ({int correct, int wrong, int blank, double grade}) _score() {
    final total = widget.questions.length;
    var correct = 0;
    var wrong = 0;
    var blank = 0;
    for (var i = 0; i < total; i++) {
      final a = _answers[i];
      if (a == null) {
        blank++;
      } else if (a == widget.questions[i].correctIndex) {
        correct++;
      } else {
        wrong++;
      }
    }
    final raw = widget.penalty ? correct - wrong / 3 : correct.toDouble();
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
    if (widget.record) {
      final ds = ref.read(subjectsDataSourceProvider);
      unawaited(ds.recordStudyToday());
      unawaited(ds.recordExamAttempt(
        subjectId: widget.subjectId,
        questions: widget.questions,
        answers: _answers,
        grade: _score().grade,
        penalty: widget.penalty,
        timed: widget.timed,
        minutes: widget.minutes,
        elapsedSeconds: _elapsed,
        nodeIds: widget.nodeIds,
      ),);
      ref.invalidate(examAttemptsProvider(widget.subjectId));
    }
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

  /// Cabecera común del modal (título + acción a la derecha).
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
            Icon(Icons.fact_check_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              l.studioTest,
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
                    // Pregunta sobre fondo azul claro, con su número (1/50).
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
                            q.question,
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Respuestas A/B/C/D en tarjetas.
                    for (var i = 0; i < q.options.length; i++)
                      _optionCard(
                        context,
                        index: i,
                        text: q.options[i],
                        selected: _answers[_cur] == i,
                        onTap: () => setState(
                          () => _answers[_cur] = _answers[_cur] == i ? null : i,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        // Navegación: atrás / contador / siguiente.
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

  /// Repaso PAGINADO: una pregunta a la vez (igual que al hacer el test) con
  /// Anterior/Siguiente y un botón de Finalizar siempre visible para salir.
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
    final hasSection = q.nodeId != null;
    final open = _expanded.contains(i);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${i + 1}. ${q.question}',
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var j = 0; j < q.options.length; j++)
            _optionCard(
              context,
              index: j,
              text: q.options[j],
              selected: mine == j,
              correct: j == q.correctIndex,
              readOnly: true,
              // Icono "ver" junto a la respuesta correcta: despliega aquí mismo
              // el temario original + la explicación de la IA de esa sección.
              trailing: (hasSection && j == q.correctIndex)
                  ? IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: l.studyTestViewInMaterial,
                      icon: Icon(
                        open
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: Colors.green.shade700,
                      ),
                      onPressed: () => setState(() {
                        if (open) {
                          _expanded.remove(i);
                        } else {
                          _expanded.add(i);
                        }
                      }),
                    )
                  : null,
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
          if (open && hasSection) _reviewDetail(context, q.nodeId!),
        ],
      ),
    );
  }

  /// Panel que se despliega bajo una pregunta: el temario ORIGINAL de su
  /// sección y el EXPLICADO generado por la IA.
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

  /// Un bloque (Original o Explicado) del contenido de la sección, leído del
  /// provider de contenido de nodos. Se omite si está vacío.
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

  Widget _optionCard(
    BuildContext context, {
    required int index,
    required String text,
    required bool selected,
    bool? correct,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final scheme = context.colors;
    final letter = String.fromCharCode(65 + index); // A, B, C, D…
    Color border = scheme.outlineVariant;
    Color badgeBg = scheme.surfaceContainerHighest;
    Color badgeFg = scheme.onSurfaceVariant;
    Color? bg;
    var strong = false;
    if (readOnly) {
      if (correct ?? false) {
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.10);
        badgeBg = Colors.green;
        badgeFg = Colors.white;
        strong = true;
      } else if (selected) {
        border = scheme.error;
        bg = scheme.error.withValues(alpha: 0.10);
        badgeBg = scheme.error;
        badgeFg = scheme.onError;
        strong = true;
      }
    } else if (selected) {
      border = scheme.primary;
      bg = scheme.primary.withValues(alpha: 0.10);
      badgeBg = scheme.primary;
      badgeFg = scheme.onPrimary;
      strong = true;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: strong ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: badgeBg, shape: BoxShape.circle),
                child: Text(
                  letter,
                  style: context.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800, color: badgeFg),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(text, style: context.textTheme.bodyLarge),
              ),
              if (readOnly && (correct ?? false))
                const Icon(Icons.check_circle, size: 18, color: Colors.green),
              if (readOnly && selected && !(correct ?? false)) ...[
                Text(
                  context.l10n.studyTestYourAnswer,
                  style: context.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.error,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.cancel, size: 18, color: scheme.error),
              ],
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
