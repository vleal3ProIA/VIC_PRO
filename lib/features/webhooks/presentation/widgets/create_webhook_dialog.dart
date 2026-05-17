import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/webhooks_providers.dart';
import '../../data/webhooks_datasource.dart';
import '../../domain/webhook_endpoint.dart';

/// Dialog para registrar un nuevo endpoint webhook. Pide URL,
/// descripción opcional y eventos a suscribir.
class CreateWebhookDialog extends ConsumerStatefulWidget {
  const CreateWebhookDialog({super.key});

  @override
  ConsumerState<CreateWebhookDialog> createState() =>
      _CreateWebhookDialogState();
}

class _CreateWebhookDialogState extends ConsumerState<CreateWebhookDialog> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _wildcardMode = true;
  final Set<String> _selectedEvents = {};
  bool _saving = false;
  String? _errorMsg;

  /// Eventos visibles cuando se desactiva el wildcard. Mantener
  /// sincronizados con `VALID_EVENTS` en `webhook-dispatch/index.ts`.
  static const _availableEvents = <String>[
    'user.created',
    'user.deleted',
    'subscription.created',
    'subscription.updated',
    'subscription.canceled',
    'invoice.paid',
    'invoice.failed',
  ];

  @override
  void dispose() {
    _urlCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return AlertDialog(
      title: Text(l.webhooksCreateDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _urlCtrl,
                  enabled: !_saving,
                  keyboardType: TextInputType.url,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.webhooksFieldUrl,
                    helperText: l.webhooksFieldUrlHint,
                    prefixIcon: const Icon(Icons.link),
                    hintText: 'https://example.com/webhooks',
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return l.webhooksUrlRequired;
                    final ok = Uri.tryParse(s);
                    if (ok == null ||
                        !(ok.scheme == 'https' ||
                            (ok.scheme == 'http' &&
                                (ok.host == 'localhost' ||
                                    ok.host == '127.0.0.1')))) {
                      return l.webhooksUrlInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descCtrl,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: l.webhooksFieldDescription,
                    helperText: l.webhooksFieldDescriptionHint,
                    prefixIcon: const Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.webhooksFieldEvents,
                  style: context.textTheme.labelLarge,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _wildcardMode,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _wildcardMode = v),
                  title: Text(l.webhooksEventAll),
                  subtitle: Text(l.webhooksEventAllHint),
                ),
                if (!_wildcardMode)
                  ..._availableEvents.map(
                    (ev) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _selectedEvents.contains(ev),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() {
                                if (v ?? false) {
                                  _selectedEvents.add(ev);
                                } else {
                                  _selectedEvents.remove(ev);
                                }
                              }),
                      title: Text(
                        ev,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
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
              : Text(l.webhooksCreate),
        ),
      ],
    );
  }

  Future<void> _onSubmit() async {
    final l = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final events = _wildcardMode
        ? const ['*']
        : (_selectedEvents.isEmpty
              ? const <String>[]
              : _selectedEvents.toList());
    if (events.isEmpty) {
      setState(() => _errorMsg = l.webhooksEventsRequired);
      return;
    }
    setState(() {
      _saving = true;
      _errorMsg = null;
    });
    try {
      final tenantId = ref.read(currentTenantIdProvider);
      final WebhookEndpoint created = await ref
          .read(webhooksDataSourceProvider)
          .createEndpoint(
            url: _urlCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            events: events,
            tenantId: tenantId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on WebhookException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = _friendlyError(l, e);
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMsg = l.webhooksCreateError;
        _saving = false;
      });
    }
  }

  String _friendlyError(AppLocalizations l, WebhookException e) {
    switch (e.code) {
      case 'invalid_url':
        return l.webhooksUrlInvalid;
      case 'invalid_events':
        return l.webhooksEventsRequired;
      default:
        return l.webhooksCreateError;
    }
  }
}
