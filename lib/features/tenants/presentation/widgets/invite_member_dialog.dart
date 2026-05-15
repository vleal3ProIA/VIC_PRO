import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

import '../../application/team_providers.dart';
import '../../data/tenant_invitations_datasource.dart';
import '../../domain/tenant.dart';
import '../../domain/tenant_member.dart';

/// Dialog para crear una invitación. Devuelve el `CreatedInvitation` al
/// `showDialog` cuando la creación tiene éxito; `null` si el usuario cancela.
class InviteMemberDialog extends ConsumerStatefulWidget {
  const InviteMemberDialog({required this.tenant, super.key});

  final Tenant tenant;

  @override
  ConsumerState<InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends ConsumerState<InviteMemberDialog> {
  final _email = TextEditingController();
  TenantRole _role = TenantRole.member;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String? _mapError(String code, String fallback) {
    final l = context.l10n;
    return switch (code) {
      'already_invited' => l.teamErrorAlreadyInvited,
      'not_admin' || 'not_member' => l.teamErrorNotAdmin,
      'rate_limited' => l.teamErrorRateLimited,
      _ => fallback,
    };
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = context.l10n.errorEmailInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await createInvitation(
        ref,
        tenantId: widget.tenant.id,
        email: email,
        role: _role,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on TenantInvitationException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _mapError(e.code, context.l10n.teamErrorGeneric);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10n.teamErrorGeneric;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.teamInviteTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l.teamInviteEmailLabel,
                prefixIcon: const Icon(Icons.alternate_email),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TenantRole>(
              initialValue: _role,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _role = v ?? TenantRole.member),
              decoration: InputDecoration(labelText: l.teamInviteRoleLabel),
              items: [
                DropdownMenuItem(
                  value: TenantRole.member,
                  child: Text(l.teamMemberRoleMember),
                ),
                DropdownMenuItem(
                  value: TenantRole.admin,
                  child: Text(l.teamMemberRoleAdmin),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: context.colors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Text(l.teamInviteSubmit),
        ),
      ],
    );
  }
}
