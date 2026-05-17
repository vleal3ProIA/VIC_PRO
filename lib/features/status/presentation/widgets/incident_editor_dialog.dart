import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../application/incidents_providers.dart';
import '../../domain/incident.dart';
import '../incident_visuals.dart';

/// Dialog para crear/editar un incidente. Reutilizable.
class IncidentEditorDialog extends ConsumerStatefulWidget {
  const IncidentEditorDialog({this.initial, super.key});
  final Incident? initial;

  @override
  ConsumerState<IncidentEditorDialog> createState() =>
      _IncidentEditorDialogState();
}

class _IncidentEditorDialogState extends ConsumerState<IncidentEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _componentsCtrl;
  late IncidentStatus _status;
  late IncidentSeverity _severity;
  late bool _publish;
  bool _saving = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _titleCtrl = TextEditingController(text: i?.title ?? '');
    _bodyCtrl = TextEditingController(text: i?.body ?? '');
    _componentsCtrl = TextEditingController(
      text: i?.components.join(', ') ?? '',
    );
    _status = i?.status ?? IncidentStatus.investigating;
    _severity = i?.severity ?? IncidentSeverity.minor;
    _publish = i?.published ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _componentsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isEdit = widget.initial != null;

    return AlertDialog(
      title: Text(
        isEdit ? l.adminIncidentsEdit : l.adminIncidentsCreate,
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
                  controller: _titleCtrl,
                  enabled: !_saving,
                  maxLength: 200,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.adminIncidentsFieldTitle,
                    prefixIcon: const Icon(Icons.title_outlined),
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return l.adminIncidentsTitleRequired;
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<IncidentSeverity>(
                        initialValue: _severity,
                        decoration: InputDecoration(
                          labelText: l.adminIncidentsFieldSeverity,
                          prefixIcon: const Icon(Icons.priority_high),
                        ),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() {
                                  if (v != null) _severity = v;
                                }),
                        items: [
                          for (final s in IncidentSeverity.values)
                            DropdownMenuItem(
                              value: s,
                              child: Text(
                                incidentSeverityVisuals(context, s).label(l),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<IncidentStatus>(
                        initialValue: _status,
                        decoration: InputDecoration(
                          labelText: l.adminIncidentsFieldStatus,
                          prefixIcon: const Icon(Icons.bolt_outlined),
                        ),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() {
                                  if (v != null) _status = v;
                                }),
                        items: [
                          for (final s in IncidentStatus.values)
                            DropdownMenuItem(
                              value: s,
                              child: Text(
                                incidentStatusVisuals(context, s).label(l),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _componentsCtrl,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText: l.adminIncidentsFieldComponents,
                    helperText: l.adminIncidentsFieldComponentsHint,
                    prefixIcon: const Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _bodyCtrl,
                  enabled: !_saving,
                  maxLength: 5000,
                  minLines: 3,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: l.adminIncidentsFieldBody,
                    helperText: l.adminIncidentsFieldBodyHint,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _publish,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _publish = v),
                  title: Text(l.adminIncidentsFieldPublish),
                  subtitle: Text(l.adminIncidentsFieldPublishHint),
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
      final ds = ref.read(incidentsDataSourceProvider);
      final components = _componentsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final Incident result;
      if (widget.initial == null) {
        result = await ds.create(
          title: _titleCtrl.text.trim(),
          body: _bodyCtrl.text.trim(),
          status: _status,
          severity: _severity,
          components: components,
          published: _publish,
        );
      } else {
        result = await ds.update(
          id: widget.initial!.id,
          title: _titleCtrl.text.trim(),
          body: _bodyCtrl.text.trim(),
          status: _status,
          severity: _severity,
          components: components,
          startedAt: widget.initial!.startedAt,
          published: _publish,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMsg = l.adminIncidentsSaveError;
        _saving = false;
      });
    }
  }
}
