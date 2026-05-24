// ============================================================================
// subjects · "Mis temarios" (Fase 2) — destino /home, layout NotebookLM
// ----------------------------------------------------------------------------
// Barra superior: selector del temario (recuerda el último usado) + botón de
// añadir + borrar. Debajo, a pantalla completa, el workspace de 3 columnas
// (índice · contenido · estudio) en `SubjectStudyPanel`.
// ============================================================================

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
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateSubjectDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final created = await _ds.createSubject(title.trim());
      ref.invalidate(subjectsListProvider);
      if (mounted) _select(created.id);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.subjectsLoadError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(subjectsListProvider);

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
              ),
              const Divider(height: 1),
              Expanded(
                child: AppEmptyState(
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
            ),
            const Divider(height: 1),
            Expanded(
              child: SubjectStudyPanel(
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
  });

  final List<Subject> subjects;
  final Subject? selected;
  final bool busy;
  final ValueChanged<String> onSelect;
  final VoidCallback? onAdd;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
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
                  onChanged: busy ? null : (v) => v != null ? onSelect(v) : null,
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
          PremiumButton(
            label: l.subjectsAdd,
            leadingIcon: Icons.add,
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

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.subjectsNewTitle),
      content: AppTextField(
        controller: _name,
        label: l.subjectsNameField,
        prefixIcon: Icons.menu_book_outlined,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l.actionSave),
        ),
      ],
    );
  }

  void _submit() {
    final t = _name.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(t);
  }
}
