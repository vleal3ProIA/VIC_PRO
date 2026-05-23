// ============================================================================
// subjects · "Mis temarios" (Fase 1b) — se renderiza en /home
// ----------------------------------------------------------------------------
// Desplegable de temarios + crear + abrir un temario para subir archivos y ver
// su estado de procesado (queued/processing -> ready/failed) con polling.
// Es el primer pedazo del layout estilo NotebookLM; la Fase 2 añadirá la card
// central (3 pestañas) y los recursos a la derecha.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/subjects_providers.dart';
import '../../data/subjects_datasource.dart';
import '../../domain/subject.dart';
import '../util/file_picker_web.dart';

class SubjectsHome extends ConsumerStatefulWidget {
  const SubjectsHome({super.key});

  @override
  ConsumerState<SubjectsHome> createState() => _SubjectsHomeState();
}

class _SubjectsHomeState extends ConsumerState<SubjectsHome> {
  String? _selectedId;
  bool _busy = false;

  SubjectsDataSource get _ds => ref.read(subjectsDataSourceProvider);

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
      if (mounted) setState(() => _selectedId = created.id);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text(l.subjectsLoadError),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSubject(Subject s) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.subjectsDeleteTitle),
        content: Text(l.subjectsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.aiDeleteCta),
          ),
        ],
      ),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: l.homeSubjectsTitle,
                subtitle: l.homeSubjectsSubtitle,
                actions: [
                  PremiumButton(
                    label: l.subjectsAdd,
                    leadingIcon: Icons.add,
                    loading: _busy,
                    onPressed: _busy ? null : _createSubject,
                  ),
                ],
              ),
              AppSpacing.gapLg,
              async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: AppLoadingState(),
                ),
                error: (e, _) => AppErrorState(
                  message: l.subjectsLoadError,
                  detail: e.toString(),
                  onRetry: () => ref.invalidate(subjectsListProvider),
                  retryLabel: l.actionRetry,
                ),
                data: (subjects) => _buildBody(context, subjects),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<Subject> subjects) {
    final l = context.l10n;
    if (subjects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: AppEmptyState(
          icon: Icons.menu_book_outlined,
          title: l.subjectsEmptyTitle,
          message: l.subjectsEmptyBody,
        ),
      );
    }

    final selected = subjects.firstWhere(
      (s) => s.id == _selectedId,
      orElse: () => subjects.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Desplegable de temarios + borrar el seleccionado.
        PremiumCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(Icons.menu_book_outlined, color: context.colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selected.id,
                    items: [
                      for (final s in subjects)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged:
                        _busy ? null : (v) => setState(() => _selectedId = v),
                  ),
                ),
              ),
              IconButton(
                tooltip: l.aiDeleteCta,
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : () => _deleteSubject(selected),
              ),
            ],
          ),
        ),
        AppSpacing.gapMd,
        _DocumentsPanel(key: ValueKey(selected.id), subjectId: selected.id),
      ],
    );
  }
}

/// Panel de documentos de un temario: lista con estado + subir archivo.
/// Hace polling mientras algún documento esté en proceso.
class _DocumentsPanel extends ConsumerStatefulWidget {
  const _DocumentsPanel({required this.subjectId, super.key});

  final String subjectId;

  @override
  ConsumerState<_DocumentsPanel> createState() => _DocumentsPanelState();
}

class _DocumentsPanelState extends ConsumerState<_DocumentsPanel> {
  Timer? _poll;
  bool _uploading = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPolling(List<SubjectDocument> docs) {
    final anyInProgress = docs.any((d) => d.inProgress);
    if (anyInProgress) {
      if (_poll == null || !_poll!.isActive) {
        _poll = Timer.periodic(const Duration(seconds: 4), (_) {
          if (!mounted) {
            _poll?.cancel();
            return;
          }
          ref.invalidate(subjectDocumentsProvider(widget.subjectId));
        });
      }
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _upload() async {
    if (_uploading) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    final picked = await pickFile();
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(subjectsDataSourceProvider).uploadDocument(
            subjectId: widget.subjectId,
            file: picked,
          );
      ref.invalidate(subjectDocumentsProvider(widget.subjectId));
      messenger.showSnackBar(SnackBar(content: Text(l.subjectUploaded)));
    } on SubjectsException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.subjectUploadError} (${e.code})'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text(l.subjectUploadError),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteDoc(SubjectDocument doc) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(subjectsDataSourceProvider).deleteDocument(doc);
    ref.invalidate(subjectDocumentsProvider(widget.subjectId));
    if (mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l.subjectDocDeleted)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(subjectDocumentsProvider(widget.subjectId));
    async.whenData(_syncPolling);

    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.subjectDocsTitle,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(l.subjectUpload),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: AppLoadingState(),
            ),
            error: (e, _) => AppErrorState(
              message: l.subjectsLoadError,
              detail: e.toString(),
              onRetry: () =>
                  ref.invalidate(subjectDocumentsProvider(widget.subjectId)),
              retryLabel: l.actionRetry,
            ),
            data: (docs) {
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    l.subjectNoDocs,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final d in docs) _DocRow(doc: d, onDelete: _deleteDoc),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.doc, required this.onDelete});

  final SubjectDocument doc;
  final Future<void> Function(SubjectDocument) onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.fileName ?? doc.storagePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium,
                ),
                if (doc.status == DocStatus.failed && doc.error != null)
                  Text(
                    doc.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatusChip(status: doc.status),
          IconButton(
            tooltip: l.aiDeleteCta,
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => onDelete(doc),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final DocStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    switch (status) {
      case DocStatus.queued:
        return PremiumBadge(
          label: l.docStatusQueued,
          variant: PremiumBadgeVariant.neutral,
          dense: true,
        );
      case DocStatus.processing:
        return PremiumBadge(
          label: l.docStatusProcessing,
          variant: PremiumBadgeVariant.info,
          dense: true,
        );
      case DocStatus.ready:
        return PremiumBadge(
          label: l.docStatusReady,
          variant: PremiumBadgeVariant.success,
          dense: true,
        );
      case DocStatus.failed:
        return PremiumBadge(
          label: l.docStatusFailed,
          variant: PremiumBadgeVariant.error,
          dense: true,
        );
    }
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
