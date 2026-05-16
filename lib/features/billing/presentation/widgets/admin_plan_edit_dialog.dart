import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

import '../../application/admin_plans_providers.dart';
import '../../data/admin_plans_datasource.dart';
import '../../domain/plan.dart';

/// Diálogo de edición de un plan (admin only).
///
/// Editables:
///   - name, description, position, is_active
///   - features (editor JSON sencillo)
///
/// NO editables aquí (vendrá en 1.F.2):
///   - precios (`price_monthly_cents` / `price_yearly_cents`) — su cambio
///     requiere migración de Stripe Price, que es un flujo separado.
///   - slug — es identificador inmutable.
///
/// Devuelve `true` por `Navigator.pop` si guardó con éxito; `false`/null
/// si canceló o falló.
class AdminPlanEditDialog extends ConsumerStatefulWidget {
  const AdminPlanEditDialog({required this.plan, super.key});

  final Plan plan;

  @override
  ConsumerState<AdminPlanEditDialog> createState() =>
      _AdminPlanEditDialogState();
}

class _AdminPlanEditDialogState extends ConsumerState<AdminPlanEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _positionCtrl;
  late final TextEditingController _featuresCtrl;
  late bool _isActive;
  bool _busy = false;
  String? _error;
  String? _featuresError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.plan.name);
    _descCtrl = TextEditingController(text: widget.plan.description ?? '');
    _positionCtrl =
        TextEditingController(text: widget.plan.position.toString());
    _featuresCtrl = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(widget.plan.features),
    );
    _isActive = widget.plan.isActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _positionCtrl.dispose();
    _featuresCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    setState(() {
      _busy = true;
      _error = null;
      _featuresError = null;
    });

    // Validar features JSON.
    Map<String, dynamic>? features;
    try {
      final decoded = jsonDecode(_featuresCtrl.text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('features must be a JSON object');
      }
      features = decoded;
    } catch (e) {
      setState(() {
        _busy = false;
        _featuresError = context.l10n.adminPlansFeaturesInvalid;
      });
      return;
    }

    final position = int.tryParse(_positionCtrl.text);
    if (position == null) {
      setState(() {
        _busy = false;
        _error = context.l10n.adminPlansPositionInvalid;
      });
      return;
    }

    try {
      final ds = ref.read(adminPlansDataSourceProvider);
      final result = await ds.updateMetadata(
        planId: widget.plan.id,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        features: features,
        position: position,
        isActive: _isActive,
      );
      if (!mounted) return;
      if (result.stripeSyncWarning != null) {
        // Guardó en BD pero el sync de Stripe falló. Lo avisamos sin
        // bloquear (el siguiente save reintenta).
        context.showSnack(
          context.l10n.adminPlansSavedStripeWarn(result.stripeSyncWarning!),
        );
      } else {
        context.showSnack(context.l10n.adminPlansSaved);
      }
      Navigator.of(context).pop(true);
    } on AdminPlanException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _mapError(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10n.adminPlansSaveError;
      });
    }
  }

  String _mapError(String code) {
    final l = context.l10n;
    return switch (code) {
      'not_admin' => l.adminPlansNotAdmin,
      'nothing_to_update' => l.adminPlansSaveError,
      _ => l.adminPlansSaveError,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.adminPlansEditTitle(widget.plan.slug)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                enabled: !_busy,
                decoration: InputDecoration(labelText: l.adminPlansFieldName),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                enabled: !_busy,
                minLines: 1,
                maxLines: 3,
                decoration:
                    InputDecoration(labelText: l.adminPlansFieldDescription),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _positionCtrl,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.adminPlansFieldPosition,
                        helperText: l.adminPlansFieldPositionHelp,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.adminPlansFieldActive,
                        style: context.textTheme.bodySmall,
                      ),
                      Switch(
                        value: _isActive,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l.adminPlansFieldFeatures,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _featuresCtrl,
                enabled: !_busy,
                minLines: 6,
                maxLines: 12,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  helperText: l.adminPlansFieldFeaturesHelp,
                  errorText: _featuresError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // Sección read-only de precios — el cambio de precio
              // lo hace la PR 1.F.2 con su propio flujo de migración.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.adminPlansPricesReadOnlyTitle,
                      style: context.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.adminPlansPricesReadOnlyHint,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: [
                        Text(
                          'monthly: ${widget.plan.formatPrice(yearly: false)}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'yearly: ${widget.plan.formatPrice(yearly: true)}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: context.colors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _busy ? null : _onSave,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Text(MaterialLocalizations.of(context).saveButtonLabel),
        ),
      ],
    );
  }
}
