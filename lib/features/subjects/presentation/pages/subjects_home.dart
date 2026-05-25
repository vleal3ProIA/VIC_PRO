// ============================================================================
// subjects · "Mis temarios" (Fase 2) — destino /home, layout NotebookLM
// ----------------------------------------------------------------------------
// Barra superior: selector del temario (recuerda el último usado) + botón de
// añadir + borrar. Debajo, a pantalla completa, el workspace de 3 columnas
// (índice · contenido · estudio) en `SubjectStudyPanel`.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/subjects_providers.dart';
import '../../data/subjects_datasource.dart';
import '../../domain/subject.dart';
import '../util/file_picker_web.dart';
import 'subject_study_panel.dart';

const String _kPrefLastSubject = 'study_last_subject';

class SubjectsHome extends ConsumerStatefulWidget {
  const SubjectsHome({super.key});

  @override
  ConsumerState<SubjectsHome> createState() => _SubjectsHomeState();
}

class _SubjectsHomeState extends ConsumerState<SubjectsHome> {
  String? _selectedId;
  bool _busy = false;

  SubjectsDataSource get _ds => ref.read(subjectsDataSourceProvider);

  @override
  void initState() {
    super.initState();
    _selectedId =
        ref.read(sharedPreferencesProvider).getString(_kPrefLastSubject);
  }

  void _select(String id) {
    setState(() => _selectedId = id);
    ref.read(sharedPreferencesProvider).setString(_kPrefLastSubject, id);
  }

  Future<void> _createSubject() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    // El modal pide nombre (obligatorio) y, opcionalmente, el archivo del
    // temario: así se crea y se sube de una vez.
    final result = await showDialog<({String title, PickedFile? file})>(
      context: context,
      builder: (_) => const _CreateSubjectDialog(),
    );
    if (result == null || result.title.trim().isEmpty) return;
    setState(() => _busy = true);
    String? createdId;
    var uploaded = false;
    try {
      final created = await _ds.createSubject(result.title.trim());
      createdId = created.id;
      if (result.file != null) {
        await _ds.uploadDocument(subjectId: created.id, file: result.file!);
        uploaded = true;
      }
      ref.invalidate(subjectsListProvider);
    } on SubjectsException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.subjectUploadError} (${e.code})'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.subjectsLoadError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || createdId == null) return;
    _select(createdId);
    // Si se subió documento, abrimos el asistente guiado: procesando → generar
    // índice → revisar → validar (o volver a generar).
    if (uploaded) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SubjectSetupWizard(subjectId: createdId!),
      );
    }
  }

  Future<void> _deleteSubject(Subject s) async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.subjectsDeleteTitle,
      body: l.subjectsDeleteBody,
      confirmLabel: l.aiDeleteCta,
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _ds.deleteSubject(s.id);
      ref.invalidate(subjectsListProvider);
      if (mounted && _selectedId == s.id) setState(() => _selectedId = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setExamDate(Subject s) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: s.examDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 6),
    );
    if (picked == null) return;
    await _ds.setExamDate(s.id, picked);
    ref.invalidate(subjectsListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(subjectsListProvider);

    // Fondo oscuro SOLO detrás de las columnas (no en la barra superior, que
    // queda transparente sobre el fondo de la app). Así las cards "flotan" y
    // se ven los huecos, pero la barra del tema + botón no parece una card.
    Widget workspace(Widget child) => Expanded(
          child: ColoredBox(
            color: context.colors.surfaceContainerLowest,
            child: child,
          ),
        );

    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => Center(
        child: AppErrorState(
          message: l.subjectsLoadError,
          detail: e.toString(),
          onRetry: () => ref.invalidate(subjectsListProvider),
          retryLabel: l.actionRetry,
        ),
      ),
      data: (subjects) {
        if (subjects.isEmpty) {
          return Column(
            children: [
              _TopBar(
                subjects: const [],
                selected: null,
                busy: _busy,
                onSelect: _select,
                onAdd: _busy ? null : _createSubject,
                onDelete: null,
                onSetExamDate: null,
              ),
              workspace(
                AppEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: l.subjectsEmptyTitle,
                  message: l.subjectsEmptyBody,
                ),
              ),
            ],
          );
        }

        final selected = subjects.firstWhere(
          (s) => s.id == _selectedId,
          orElse: () => subjects.first,
        );

        return Column(
          children: [
            _TopBar(
              subjects: subjects,
              selected: selected,
              busy: _busy,
              onSelect: _select,
              onAdd: _busy ? null : _createSubject,
              onDelete: _busy ? null : () => _deleteSubject(selected),
              onSetExamDate: _busy ? null : () => _setExamDate(selected),
            ),
            workspace(
              SubjectStudyPanel(
                key: ValueKey('study_${selected.id}'),
                subject: selected,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Barra superior: selector de temario + añadir + borrar.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.subjects,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onSetExamDate,
  });

  final List<Subject> subjects;
  final Subject? selected;
  final bool busy;
  final ValueChanged<String> onSelect;
  final VoidCallback? onAdd;
  final VoidCallback? onDelete;
  final VoidCallback? onSetExamDate;

  String _examLabel(BuildContext context) {
    final l = context.l10n;
    final d = selected?.daysToExam;
    if (d == null) return l.studyExamLabel;
    if (d > 0) return l.studyExamIn(d);
    if (d == 0) return l.studyExamToday;
    return l.studyExamPast;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.menu_book_outlined, color: context.colors.primary),
          const SizedBox(width: AppSpacing.sm),
          if (selected != null)
            Flexible(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selected!.id,
                  isDense: true,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (final s in subjects)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                  onChanged:
                      busy ? null : (v) => v != null ? onSelect(v) : null,
                ),
              ),
            )
          else
            Text(
              l.homeSubjectsTitle,
              style: context.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          if (selected != null)
            IconButton(
              tooltip: l.aiDeleteCta,
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          const Spacer(),
          if (selected != null) ...[
            ActionChip(
              avatar: const Icon(Icons.event_outlined, size: 16),
              label: Text(_examLabel(context)),
              onPressed: onSetExamDate,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          PremiumButton(
            label: l.subjectsAdd,
            leadingIcon: Icons.add,
            size: PremiumButtonSize.sm,
            loading: busy,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _CreateSubjectDialog extends StatefulWidget {
  const _CreateSubjectDialog();

  @override
  State<_CreateSubjectDialog> createState() => _CreateSubjectDialogState();
}

class _CreateSubjectDialogState extends State<_CreateSubjectDialog> {
  late final TextEditingController _name;
  PickedFile? _file;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController()..addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _name
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final f = await pickFile();
      if (f != null && mounted) setState(() => _file = f);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    final t = _name.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop((title: t, file: _file));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final canSave = _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(l.subjectsNewTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: l.subjectsNameField,
            prefixIcon: Icons.menu_book_outlined,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _picking ? null : _pick,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: Text(l.subjectUpload),
          ),
          if (_file != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 16, color: scheme.primary,),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _file!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: canSave ? _submit : null,
          child: Text(l.actionSave),
        ),
      ],
    );
  }
}

/// Asistente guiado tras subir un temario: procesa el documento → genera el
/// índice → lo muestra para que el usuario lo valide o lo vuelva a generar.
/// Las fases se derivan del estado real (documento + índice) con sondeo cada
/// 3 s, así avanza solo a medida que el backend progresa.
class _SubjectSetupWizard extends ConsumerStatefulWidget {
  const _SubjectSetupWizard({required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<_SubjectSetupWizard> createState() =>
      _SubjectSetupWizardState();
}

class _SubjectSetupWizardState extends ConsumerState<_SubjectSetupWizard> {
  Timer? _poll;
  bool _busy = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPoll(bool active) {
    if (active) {
      _poll ??= Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) {
          _poll?.cancel();
          _poll = null;
          return;
        }
        ref
          ..invalidate(subjectDocumentsProvider(widget.subjectId))
          ..invalidate(subjectsListProvider)
          ..invalidate(indexNodesProvider(widget.subjectId));
      });
    } else if (_poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  Future<void> _generate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(subjectsDataSourceProvider)
          .generateIndex(widget.subjectId);
      ref.invalidate(subjectsListProvider);
    } on SubjectsException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.studyIndexFailed} (${e.code})'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.studyIndexFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _validate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    final nav = Navigator.of(context);
    try {
      await ref
          .read(subjectsDataSourceProvider)
          .validateIndex(widget.subjectId);
      ref.invalidate(subjectsListProvider);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l.studyIndexValidated)));
        nav.pop();
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.studyViewError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    final subjects =
        ref.watch(subjectsListProvider).valueOrNull ?? const <Subject>[];
    Subject? subject;
    for (final s in subjects) {
      if (s.id == widget.subjectId) {
        subject = s;
        break;
      }
    }
    final docs =
        ref.watch(subjectDocumentsProvider(widget.subjectId)).valueOrNull ??
            const <SubjectDocument>[];
    final nodes =
        ref.watch(indexNodesProvider(widget.subjectId)).valueOrNull ??
            const <IndexNode>[];

    final docInProgress = docs.any((d) => d.inProgress);
    final docReady = docs.any((d) => d.status == DocStatus.ready);
    final docFailed = !docReady && !docInProgress && docs.isNotEmpty;
    final indexStatus = subject?.indexStatus ?? IndexStatus.none;
    final generating = indexStatus == IndexStatus.generating;
    final reviewable = indexStatus == IndexStatus.ready && nodes.isNotEmpty;

    // Sondeo activo mientras procesa el documento o genera el índice.
    _syncPoll((docInProgress || generating) && !reviewable);

    final Widget body;
    final List<Widget> actions;
    final String title;

    if (!docReady && !docFailed) {
      title = l.studySetupTitle;
      body = _status(spinner: true, text: l.studySetupProcessing);
      actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.studySetupLater),
        ),
      ];
    } else if (docFailed) {
      title = l.studySetupTitle;
      body = _status(spinner: false, text: l.subjectUploadError, error: true);
      actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
        ),
      ];
    } else if (generating || (_busy && !reviewable)) {
      title = l.studySetupTitle;
      body = _status(spinner: true, text: l.studyIndexGenerating);
      actions = const [];
    } else if (reviewable) {
      title = l.studySetupReview;
      body = _review(nodes);
      actions = [
        OutlinedButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(l.studySetupRegenerate),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _validate,
          icon: const Icon(Icons.check, size: 16),
          label: Text(l.studyValidateIndex),
        ),
      ];
    } else if (indexStatus == IndexStatus.failed) {
      title = l.studySetupTitle;
      body = _status(spinner: false, text: l.studyIndexFailed, error: true);
      actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.studySetupLater),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(l.studySetupRegenerate),
        ),
      ];
    } else {
      // Documento listo, sin índice todavía.
      title = l.studySetupTitle;
      body = _status(spinner: false, text: l.studySetupReady);
      actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.studySetupLater),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: Text(l.studyGenerateIndex),
        ),
      ];
    }

    return AlertDialog(
      title: Text(title),
      content: SizedBox(width: 460, child: body),
      actions: actions,
    );
  }

  Widget _status({
    required bool spinner,
    required String text,
    bool error = false,
  }) {
    final scheme = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spinner)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: CircularProgressIndicator(),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              size: 40,
              color: error ? scheme.error : Colors.green,
            ),
          ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium,
        ),
      ],
    );
  }

  /// Vista del índice generado (árbol indentado, solo lectura) para revisarlo.
  Widget _review(List<IndexNode> nodes) {
    final scheme = context.colors;
    final byParent = <String?, List<IndexNode>>{};
    for (final n in nodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.position.compareTo(b.position));
    }
    final rows = <Widget>[];
    void emit(IndexNode n) {
      final children = byParent[n.id] ?? const <IndexNode>[];
      final isFolder = children.isNotEmpty;
      rows.add(
        Padding(
          padding: EdgeInsets.only(left: 4 + n.depth * 14.0, top: 3, bottom: 3),
          child: Row(
            children: [
              Icon(
                isFolder ? Icons.folder_rounded : Icons.fiber_manual_record,
                size: isFolder ? 15 : 8,
                color: isFolder ? Colors.amber.shade700 : scheme.onSurface,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  n.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: isFolder ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      for (final c in children) {
        emit(c);
      }
    }

    for (final r in byParent[null] ?? const <IndexNode>[]) {
      emit(r);
    }
    return SizedBox(
      height: 360,
      child: Scrollbar(child: ListView(children: rows)),
    );
  }
}
