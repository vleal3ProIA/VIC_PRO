import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/tokens_providers.dart';
import '../../data/tokens_datasource.dart';
import '../../domain/personal_access_token.dart';

/// Dialog para crear un nuevo PAT. Pide nombre, scopes y caducidad.
/// Al éxito hace `pop(PersonalAccessToken)` con el secret en `.secret`.
class CreateTokenDialog extends ConsumerStatefulWidget {
  const CreateTokenDialog({super.key});

  @override
  ConsumerState<CreateTokenDialog> createState() =>
      _CreateTokenDialogState();
}

class _CreateTokenDialogState extends ConsumerState<CreateTokenDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final Set<String> _scopes = {'read'};
  int? _expiresInDays = 90;
  bool _saving = false;
  String? _errorMsg;

  static const _expiryOptions = <int?>[7, 30, 90, 180, 365, null];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return AlertDialog(
      title: Text(l.tokensCreateDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  enabled: !_saving,
                  maxLength: 80,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.tokensFieldName,
                    helperText: l.tokensFieldNameHint,
                    prefixIcon: const Icon(Icons.label_outline),
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return l.tokensNameRequired;
                    if (s.length > 80) return l.tokensNameTooLong;
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  l.tokensFieldScopes,
                  style: context.textTheme.labelLarge,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _scopes.contains('read'),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                            if (v ?? false) {
                              _scopes.add('read');
                            } else {
                              _scopes.remove('read');
                            }
                          }),
                  title: Text(l.tokensScopeRead),
                  subtitle: Text(l.tokensScopeReadHint),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _scopes.contains('write'),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                            if (v ?? false) {
                              _scopes.add('write');
                            } else {
                              _scopes.remove('write');
                            }
                          }),
                  title: Text(l.tokensScopeWrite),
                  subtitle: Text(l.tokensScopeWriteHint),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
                const SizedBox(height: 8),
                Text(
                  l.tokensFieldExpiration,
                  style: context.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: _expiresInDays,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _expiresInDays = v),
                  items: [
                    for (final days in _expiryOptions)
                      DropdownMenuItem(
                        value: days,
                        child: Text(_expiryLabel(l, days)),
                      ),
                  ],
                ),
                if (_expiresInDays == null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 18,
                        color: context.colors.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l.tokensNoExpiryWarning,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
          onPressed: _saving || _scopes.isEmpty ? null : _onSubmit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.tokensCreate),
        ),
      ],
    );
  }

  String _expiryLabel(AppLocalizations l, int? days) {
    if (days == null) return l.tokensExpiryNever;
    return l.tokensExpiryDays(days);
  }

  Future<void> _onSubmit() async {
    final l = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_scopes.isEmpty) {
      setState(() => _errorMsg = l.tokensScopesRequired);
      return;
    }
    setState(() {
      _saving = true;
      _errorMsg = null;
    });
    try {
      final ds = ref.read(tokensDataSourceProvider);
      final PersonalAccessToken created = await ds.create(
        name: _nameCtrl.text.trim(),
        scopes: _scopes.toList(),
        expiresInDays: _expiresInDays,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on TokenException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = _friendlyError(l, e);
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMsg = l.tokensCreateError;
        _saving = false;
      });
    }
  }

  String _friendlyError(AppLocalizations l, TokenException e) {
    switch (e.code) {
      case 'invalid_name':
        return l.tokensNameRequired;
      case 'empty_scopes':
      case 'invalid_scope':
        return l.tokensScopesRequired;
      case 'invalid_expires_in_days':
        return l.tokensExpiryInvalid;
      case 'rate_limited':
        return l.tokensRateLimited;
      default:
        return l.tokensCreateError;
    }
  }
}
