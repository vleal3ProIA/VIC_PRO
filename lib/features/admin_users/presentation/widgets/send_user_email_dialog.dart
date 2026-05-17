import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../application/admin_users_providers.dart';
import '../../domain/admin_user.dart';

/// Dialog para enviar un email individual a un user. Usa el template
/// `broadcast` (subject + body custom). Se envía en el idioma del user
/// receptor (no en el del admin).
class SendUserEmailDialog extends ConsumerStatefulWidget {
  const SendUserEmailDialog({required this.user, super.key});
  final AdminUserSummary user;

  @override
  ConsumerState<SendUserEmailDialog> createState() =>
      _SendUserEmailDialogState();
}

class _SendUserEmailDialogState extends ConsumerState<SendUserEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _saving = false;
  String? _errorMsg;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.adminUsersSendEmailDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.adminUsersSendEmailTo(
                    widget.user.email,
                    widget.user.locale.toUpperCase(),
                  ),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subjectCtrl,
                  enabled: !_saving,
                  maxLength: 200,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.adminUsersSendEmailSubject,
                    prefixIcon: const Icon(Icons.subject),
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return l.adminUsersSendEmailSubjectRequired;
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _bodyCtrl,
                  enabled: !_saving,
                  maxLength: 5000,
                  minLines: 5,
                  maxLines: 12,
                  decoration: InputDecoration(
                    labelText: l.adminUsersSendEmailBody,
                    helperText: l.adminUsersSendEmailBodyHint,
                    alignLabelWithHint: true,
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return l.adminUsersSendEmailBodyRequired;
                    return null;
                  },
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
              : Text(l.adminUsersSendEmailSend),
        ),
      ],
    );
  }

  Future<void> _onSubmit() async {
    final l = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorMsg = null;
    });
    try {
      final result = await ref
          .read(adminUsersDataSourceProvider)
          .sendEmail(
            userId: widget.user.id,
            subject: _subjectCtrl.text.trim(),
            bodyHtml: _bodyCtrl.text.trim(),
          );
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _errorMsg = l.adminUsersActionFailed(result.error ?? '?');
          _saving = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMsg = l.adminUsersSendEmailError;
        _saving = false;
      });
    }
  }
}
