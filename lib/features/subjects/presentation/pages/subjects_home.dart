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
import '../util/subject_name.dart';
import '../widgets/collapsible_index_tree.dart';
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
    final result =
        await showDialog<({String title, PickedFile? file, bool shareable})>(
      context: context,
      builder: (_) => const _CreateSubjectDialog(),
    );
    if (result == null || result.title.trim().isEmpty) return;
    setState(() => _busy = true);
    String? createdId;
    try {
      final created = await _ds.createSubject(
        result.title.trim(),
        shareable: result.shareable,
      );
      createdId = created.id;
      ref.invalidate(subjectsListProvider);
    } on SubjectsException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.subjectsLoadError} (${e.code})'),
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
    // Si hay archivo, abrimos el asistente guiado, que se encarga de TODO en
    // un modal: subiendo (barra) → procesando → generar índice → revisar →
    // validar (o volver a generar).
    if (result.file != null) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        // Fondo OPACO: durante subida/proceso/índice solo se ve el asistente.
        barrierColor: Theme.of(context).colorScheme.surface,
        builder: (_) =>
            _SubjectSetupWizard(subjectId: createdId!, initialFile: result.file),
      );
    }
  }

  Future<void> _deleteSubject(Subject s) async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.subjectsDeleteTitle,
      body: l.subjectsDeleteNamed(s.title),
      confirmLabel: l.aiDeleteCta,
      cancelLabel: l.actionCancel,
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

  /// Renombra el temario: abre un modal con el nombre actual editable. El
  /// nombre se sanea (anti-código, límite de caracteres) antes de guardar.
  Future<void> _renameSubject(Subject s) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSubjectDialog(initialName: s.title),
    );
    if (newName == null || newName.isEmpty || newName == s.title) return;
    setState(() => _busy = true);
    try {
      await _ds.renameSubject(s.id, newName);
      ref.invalidate(subjectsListProvider);
    } on SubjectsException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.subjectsLoadError} (${e.code})'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.subjectsLoadError)),
      );
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
                onEdit: null,
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
              onEdit: _busy ? null : _renameSubject,
              onDelete: _busy ? null : _deleteSubject,
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

/// Barra superior: selector de temario (desplegable con buscar/editar/borrar)
/// + chip de fecha de examen + añadir.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.subjects,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onSetExamDate,
  });

  final List<Subject> subjects;
  final Subject? selected;
  final bool busy;
  final ValueChanged<String> onSelect;
  final VoidCallback? onAdd;
  final ValueChanged<Subject>? onEdit;
  final ValueChanged<Subject>? onDelete;
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
              child: _SubjectSelector(
                subjects: subjects,
                selected: selected!,
                busy: busy,
                onSelect: onSelect,
                onEdit: onEdit,
                onDelete: onDelete,
              ),
            )
          else
            Text(
              l.homeSubjectsTitle,
              style: context.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
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

/// Selector de temario en forma de desplegable anclado bajo el nombre. Al
/// pulsar el nombre se abre hacia abajo el listado de temarios del usuario
/// (orden alfabético), mostrando hasta ~10 a la vez; si hay más de 10 se puede
/// hacer scroll y aparece un buscador que filtra SOLO entre los temarios del
/// usuario. Cada fila lleva a la derecha el icono de editar (renombrar) y el de
/// borrar.
class _SubjectSelector extends StatefulWidget {
  const _SubjectSelector({
    required this.subjects,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Subject> subjects;
  final Subject selected;
  final bool busy;
  final ValueChanged<String> onSelect;
  final ValueChanged<Subject>? onEdit;
  final ValueChanged<Subject>? onDelete;

  @override
  State<_SubjectSelector> createState() => _SubjectSelectorState();
}

class _SubjectSelectorState extends State<_SubjectSelector> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final TextEditingController _search = TextEditingController();
  String _query = '';

  static const double _rowHeight = 48;
  static const int _visibleRows = 10;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_portal.isShowing) {
      _close();
    } else {
      _portal.show();
    }
  }

  void _close() {
    if (!_portal.isShowing) return;
    _portal.hide();
    _query = '';
    _search.clear();
  }

  List<Subject> _sorted() {
    final list = [...widget.subjects]..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    return list;
  }

  List<Subject> _filtered() {
    final q = _query.trim().toLowerCase();
    final base = _sorted();
    if (q.isEmpty) return base;
    return base
        .where((s) => s.title.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.busy ? null : _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.selected.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final l = context.l10n;
    final showSearch = widget.subjects.length > _visibleRows;
    return Stack(
      children: [
        // Capa invisible a pantalla completa: tocar fuera cierra el desplegable.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
                child: StatefulBuilder(
                  builder: (context, setLocal) {
                    final filtered = _filtered();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showSearch)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                            child: TextField(
                              controller: _search,
                              autofocus: true,
                              maxLength: kSubjectSearchMaxLength,
                              inputFormatters: subjectNameFormatters(),
                              decoration: InputDecoration(
                                isDense: true,
                                counterText: '',
                                prefixIcon: const Icon(Icons.search, size: 18),
                                hintText: l.subjectsSearchHint,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onChanged: (v) => setLocal(() => _query = v),
                            ),
                          ),
                        if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 20,
                            ),
                            child: Text(
                              l.subjectsSearchEmpty,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: _rowHeight * _visibleRows,
                            ),
                            child: Scrollbar(
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: filtered.length,
                                itemBuilder: (context, i) => _row(filtered[i]),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(Subject s) {
    final l = context.l10n;
    final scheme = context.colors;
    final isSelected = s.id == widget.selected.id;
    return InkWell(
      onTap: () {
        _close();
        if (s.id != widget.selected.id) widget.onSelect(s.id);
      },
      child: SizedBox(
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              if (isSelected)
                Icon(Icons.check, size: 16, color: scheme.primary)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                tooltip: l.subjectsRename,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: widget.onEdit == null
                    ? null
                    : () {
                        _close();
                        widget.onEdit!(s);
                      },
              ),
              IconButton(
                tooltip: l.aiDeleteCta,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: widget.onDelete == null
                    ? null
                    : () {
                        _close();
                        widget.onDelete!(s);
                      },
              ),
            ],
          ),
        ),
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
  bool _shareable = false;

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
    final t = sanitizeSubjectName(_name.text);
    if (t.isEmpty) return;
    Navigator.of(context).pop((title: t, file: _file, shareable: _shareable));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final canSave = sanitizeSubjectName(_name.text).isNotEmpty;
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
            maxLength: kSubjectNameMaxLength,
            inputFormatters: subjectNameFormatters(),
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
          const SizedBox(height: AppSpacing.sm),
          // Declaración de material libre: solo así el contenido generado entra
          // en la biblioteca global del proyecto y puede reutilizarse.
          CheckboxListTile(
            value: _shareable,
            onChanged: (v) => setState(() => _shareable = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              l.subjectShareableLabel,
              style: context.textTheme.bodySmall,
            ),
            subtitle: Text(
              l.subjectShareableHint,
              style: context.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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

/// Modal para renombrar un temario: muestra el nombre actual editable. El
/// nombre se sanea (anti-código) y se limita en longitud, igual que en el
/// formulario de creación. Devuelve el nuevo nombre (saneado) o `null`.
class _RenameSubjectDialog extends StatefulWidget {
  const _RenameSubjectDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameSubjectDialog> createState() => _RenameSubjectDialogState();
}

class _RenameSubjectDialogState extends State<_RenameSubjectDialog> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName)
      ..addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _name
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _submit() {
    final t = sanitizeSubjectName(_name.text);
    if (t.isEmpty) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canSave = sanitizeSubjectName(_name.text).isNotEmpty;
    return AlertDialog(
      title: Text(l.subjectsRenameTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: l.subjectsNameField,
            prefixIcon: Icons.menu_book_outlined,
            maxLength: kSubjectNameMaxLength,
            inputFormatters: subjectNameFormatters(),
            onSubmitted: (_) => _submit(),
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
  const _SubjectSetupWizard({required this.subjectId, this.initialFile});

  final String subjectId;

  /// Si se pasa, el asistente sube este archivo al abrirse (con barra de
  /// progreso) antes de pasar a procesar/generar el índice.
  final PickedFile? initialFile;

  @override
  ConsumerState<_SubjectSetupWizard> createState() =>
      _SubjectSetupWizardState();
}

class _SubjectSetupWizardState extends ConsumerState<_SubjectSetupWizard> {
  Timer? _poll;
  bool _busy = false;
  bool _uploading = false;
  String? _uploadError;

  /// Análisis (profundo) de material reutilizable; se calcula una sola vez al
  /// llegar a la revisión del índice.
  Future<SubjectMatch>? _matchFuture;

  // Oferta de ampliación (temario escaso).
  bool _expandDismissed = false;
  bool _expanding = false;
  int? _expandedCount;

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _uploading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _doUpload());
    }
  }

  Future<void> _doUpload() async {
    final l = context.l10n;
    try {
      await ref.read(subjectsDataSourceProvider).uploadDocument(
            subjectId: widget.subjectId,
            file: widget.initialFile!,
          );
      ref.invalidate(subjectDocumentsProvider(widget.subjectId));
    } on SubjectsException catch (e) {
      _uploadError = '${l.subjectUploadError} (${e.code})';
    } catch (_) {
      _uploadError = l.subjectUploadError;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

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

    // Fase 0: subiendo el archivo (barra de progreso).
    if (_uploading) {
      return AlertDialog(
        title: Text(l.studySetupTitle),
        content: SizedBox(
          width: 460,
          child: _status(spinner: true, text: l.studySetupUploading),
        ),
        actions: const [],
      );
    }
    if (_uploadError != null) {
      return AlertDialog(
        title: Text(l.studySetupTitle),
        content: SizedBox(
          width: 460,
          child: _status(spinner: false, text: _uploadError!, error: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.actionClose),
          ),
        ],
      );
    }

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
      actions = const [];
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
      final detail = subject?.indexError;
      body = _status(
        spinner: false,
        text: detail != null && detail.isNotEmpty
            ? '${l.studyIndexFailed}\n\n$detail'
            : l.studyIndexFailed,
        error: true,
      );
      actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
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
            child: SizedBox(width: 320, child: LinearProgressIndicator()),
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

  /// Índice generado (árbol PLEGABLE) + aviso de material reutilizable detectado
  /// en la biblioteca del proyecto, para revisarlo antes de validar.
  Widget _review(List<IndexNode> nodes) {
    final h = (MediaQuery.sizeOf(context).height - 300).clamp(300.0, 820.0);
    _matchFuture ??= ref
        .read(subjectsDataSourceProvider)
        .matchSubject(widget.subjectId, deep: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<SubjectMatch>(
          future: _matchFuture,
          builder: (context, snap) {
            final m = snap.data;
            if (m == null) return const SizedBox.shrink();
            final useful = m.exact > 0 ||
                m.questions > 0 ||
                m.views > 0 ||
                m.flashcards > 0;
            if (!useful && !m.poor) return const SizedBox.shrink();
            return _matchBox(m, useful: useful);
          },
        ),
        SizedBox(height: h, child: CollapsibleIndexTree(nodes: nodes)),
      ],
    );
  }

  /// Acepta la oferta: pide al backend ampliar el temario con material del pool
  /// y refresca el índice para que aparezcan las secciones nuevas.
  Future<void> _expand() async {
    if (_expanding) return;
    setState(() => _expanding = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      final added = await ref.read(subjectsDataSourceProvider).expandSubject(
            widget.subjectId,
            folderTitle: l.studyExpandFolderTitle,
          );
      ref.invalidate(indexNodesProvider(widget.subjectId));
      if (mounted) setState(() => _expandedCount = added);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(backgroundColor: errBg, content: Text(l.studyViewError)),
        );
      }
    } finally {
      if (mounted) setState(() => _expanding = false);
    }
  }

  Widget _matchBox(SubjectMatch m, {required bool useful}) {
    final l = context.l10n;
    final scheme = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.studyLibraryTitle,
                  style: context.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (useful) ...[
                  const SizedBox(height: 2),
                  Text(
                    l.studyLibraryBody(m.exact, m.questions, m.views),
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (m.poor) _expandOffer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Oferta de ampliación: pregunta + Aceptar/Cancelar; tras aceptar muestra el
  /// resultado (cuántas secciones se añadieron, o que no había material).
  Widget _expandOffer() {
    final l = context.l10n;
    final scheme = context.colors;
    if (_expandedCount != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _expandedCount! > 0
              ? l.studyExpandDone(_expandedCount!)
              : l.studyExpandNone,
          style: context.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    if (_expanding) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (_expandDismissed) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          l.studyExpandOffer,
          style: context.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => setState(() => _expandDismissed = true),
              child: Text(l.actionCancel),
            ),
            FilledButton.icon(
              onPressed: _expand,
              icon: const Icon(Icons.add, size: 16),
              label: Text(l.studyExpandCta),
            ),
          ],
        ),
      ],
    );
  }
}
