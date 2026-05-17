import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../application/changelog_providers.dart';
import '../../domain/changelog_entry.dart';

/// Dialog para crear o editar una entrada del changelog. Reutilizable:
/// si recibe [initial], pre-rellena los campos y actualiza; si no,
/// inserta nuevo.
class ChangelogEditorDialog extends ConsumerStatefulWidget {
  const ChangelogEditorDialog({this.initial, super.key});

  final ChangelogEntry? initial;

  @override
  ConsumerState<ChangelogEditorDialog> createState() =>
      _ChangelogEditorDialogState();
}

class _ChangelogEditorDialogState extends ConsumerState<ChangelogEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _versionCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late ChangelogCategory _category;
  late bool _publish;
  bool _saving = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _versionCtrl = TextEditingController(text: i?.version ?? '');
    _titleCtrl = TextEditingController(text: i?.title ?? '');
    _bodyCtrl = TextEditingController(text: i?.body ?? '');
    _category = i?.category ?? ChangelogCategory.feature;
    _publish = i?.isPublished ?? false;
  }

  @override
  void dispose() {
    _versionCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isEdit = widget.initial != null;

    return AlertDialog(
      title: Text(
        isEdit ? l.adminChangelogEdit : l.adminChangelogCreate,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _versionCtrl,
                  enabled: !_saving,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: l.adminChangelogFieldVersion,
                    helperText: l.adminChangelogFieldVersionHint,
                    prefixIcon: const Icon(Icons.numbers_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleCtrl,
                  enabled: !_saving,
                  maxLength: 200,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.adminChangelogFieldTitle,
                    prefixIcon: const Icon(Icons.title_outlined),
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return l.adminChangelogTitleRequired;
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _bodyCtrl,
                  enabled: !_saving,
                  maxLength: 5000,
                  minLines: 4,
                  maxLines: 12,
                  decoration: InputDecoration(
                    labelText: l.adminChangelogFieldBody,
                    helperText: l.adminChangelogFieldBodyHint,
                    alignLabelWithHint: true,
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return l.adminChangelogBodyRequired;
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ChangelogCategory>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: l.adminChangelogFieldCategory,
                    prefixIcon: const Icon(Icons.category_outlined),
                  ),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                            if (v != null) _category = v;
                          }),
                  items: [
                    DropdownMenuItem(
                      value: ChangelogCategory.feature,
                      child: Text(l.changelogCategoryFeature),
                    ),
                    DropdownMenuItem(
                      value: ChangelogCategory.improvement,
                      child: Text(l.changelogCategoryImprovement),
                    ),
                    DropdownMenuItem(
                      value: ChangelogCategory.fix,
                      child: Text(l.changelogCategoryFix),
                    ),
                    DropdownMenuItem(
                      value: ChangelogCategory.security,
                      child: Text(l.changelogCategorySecurity),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _publish,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _publish = v),
                  title: Text(l.adminChangelogFieldPublish),
                  subtitle: Text(l.adminChangelogFieldPublishHint),
                ),
                if (_errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMsg!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _onSubmit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.actionSave),
        ),
      ],
    );
  }

  Future<void> _onSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l = context.l10n;
    setState(() {
      _saving = true;
      _errorMsg = null;
    });
    try {
      final ds = ref.read(changelogDataSourceProvider);
      final version = _versionCtrl.text.trim().isEmpty
          ? null
          : _versionCtrl.text.trim();
      final ChangelogEntry result;
      if (widget.initial == null) {
        result = await ds.create(
          title: _titleCtrl.text.trim(),
          body: _bodyCtrl.text.trim(),
          category: _category,
          version: version,
          publishedAt: _publish ? DateTime.now() : null,
        );
      } else {
        // Si pasamos de borrador a publicado por primera vez, set now().
        // Si ya estaba publicado y sigue publicado, conservamos el
        // publishedAt original. Si se quita el switch, lo despublicamos.
        DateTime? publishedAt;
        if (_publish) {
          publishedAt = widget.initial!.publishedAt ?? DateTime.now();
        } else {
          publishedAt = null;
        }
        result = await ds.update(
          id: widget.initial!.id,
          title: _titleCtrl.text.trim(),
          body: _bodyCtrl.text.trim(),
          category: _category,
          version: version,
          publishedAt: publishedAt,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMsg = l.adminChangelogSaveError;
        _saving = false;
      });
    }
  }
}
