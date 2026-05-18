import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/security/reauth_datasource.dart';
import 'package:myapp/core/security/reauth_providers.dart';

/// Modal que pide al user su password actual y la valida server-side.
/// Devuelve `true` si la verificacion paso (el backend registra una
/// "recent verification" valida por 5 min para el `actionKind` dado);
/// `false` si el user cancelo o el password fue incorrecto.
///
/// **Uso desde una pantalla destructiva**:
///
/// ```dart
/// final ok = await ReauthDialog.show(
///   context,
///   ref: ref,
///   actionKind: 'delete_account',
/// );
/// if (ok != true) return; // user cancelo o password incorrecto
/// // ahora invocar la Edge Function destructiva, que ya tendra
/// // la recent_verification para consumirla server-side.
/// ```
///
/// **Patron de seguridad**: ANTES (PR-F) la validacion de password se
/// hacia en el frontend con `signInWithPassword`. Un atacante con JWT
/// robado podia invocar el endpoint destructivo directamente saltando
/// el modal. Ahora el endpoint destructivo EXIGE en server una
/// `recent_verification` fresca; sin ese marker, devuelve 403.
class ReauthDialog {
  ReauthDialog._();

  /// Muestra el modal y resuelve cuando el user termina (success/cancel).
  ///
  /// - [actionKind]: identificador que se mete en la tabla
  ///   `auth_recent_verifications`. Debe coincidir con el que la Edge
  ///   Function destructiva chequea en su `consume_recent_verification`.
  ///   Whitelist server-side (ver `verify-password/index.ts`).
  ///
  /// - [titleOverride] / [messageOverride]: si quieres un texto
  ///   especifico de la accion (ej. "Confirma tu password antes de
  ///   eliminar tu cuenta"). Si no, usa el generico.
  static Future<bool?> show(
    BuildContext context, {
    required WidgetRef ref,
    required String actionKind,
    String? titleOverride,
    String? messageOverride,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReauthDialogBody(
        ref: ref,
        actionKind: actionKind,
        titleOverride: titleOverride,
        messageOverride: messageOverride,
      ),
    );
  }
}

class _ReauthDialogBody extends StatefulWidget {
  const _ReauthDialogBody({
    required this.ref,
    required this.actionKind,
    this.titleOverride,
    this.messageOverride,
  });

  final WidgetRef ref;
  final String actionKind;
  final String? titleOverride;
  final String? messageOverride;

  @override
  State<_ReauthDialogBody> createState() => _ReauthDialogBodyState();
}

class _ReauthDialogBodyState extends State<_ReauthDialogBody> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _errorCode;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorCode = null;
    });
    try {
      await widget.ref.read(reauthDataSourceProvider).verifyPassword(
            password: _passwordCtrl.text,
            actionKind: widget.actionKind,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ReauthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCode = e.code;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorCode = 'unknown';
        _submitting = false;
      });
    }
  }

  String _friendlyError(BuildContext ctx, String code) {
    final l = ctx.l10n;
    switch (code) {
      case 'invalid_password':
        return l.reauthErrorInvalidPassword;
      case 'rate_limited':
        return l.reauthErrorRateLimited;
      case 'invalid_action_kind':
      case 'missing_fields':
      case 'user_mismatch':
      case 'invalid_token':
        return l.reauthErrorGeneric;
      default:
        return l.reauthErrorGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.titleOverride ?? l.reauthDialogTitle),
      content: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.messageOverride ?? l.reauthDialogMessage,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: l.reauthPasswordLabel,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure
                      ? l.reauthShowPassword
                      : l.reauthHidePassword,
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return l.reauthPasswordRequired;
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_errorCode != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _friendlyError(context, _errorCode!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.reauthConfirm),
        ),
      ],
    );
  }
}
