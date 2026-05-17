import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/features/billing/application/admin_plans_providers.dart';

import '../../application/admin_users_providers.dart';

/// Dialog para cambiar el plan de un user — limitado a planes FREE.
/// Para upgrades de pago, mostramos un mensaje invitando a usar Stripe
/// Dashboard (más seguro que arriesgar desincronizar la BD con Stripe).
class ChangePlanDialog extends ConsumerStatefulWidget {
  const ChangePlanDialog({required this.userId, super.key});
  final String userId;

  @override
  ConsumerState<ChangePlanDialog> createState() => _ChangePlanDialogState();
}

class _ChangePlanDialogState extends ConsumerState<ChangePlanDialog> {
  String? _selectedPlanId;
  bool _saving = false;
  String? _errorMsg;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plansAsync = ref.watch(allPlansAdminProvider);

    return AlertDialog(
      title: Text(l.adminUsersChangePlanTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: plansAsync.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => Text(l.adminUsersChangePlanLoadError),
          data: (plans) {
            final freePlans = plans.where((p) => p.isFree).toList();
            final paidPlans = plans.where((p) => !p.isFree).toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.adminUsersChangePlanBody,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (freePlans.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      l.adminUsersChangePlanNoFreePlans,
                      style: TextStyle(color: context.colors.error),
                    ),
                  )
                else
                  for (final p in freePlans)
                    // ignore: deprecated_member_use
                    RadioListTile<String>(
                      value: p.id,
                      // ignore: deprecated_member_use
                      groupValue: _selectedPlanId,
                      // ignore: deprecated_member_use
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _selectedPlanId = v),
                      title: Text(p.name),
                      subtitle: Text(
                        p.description ?? l.adminUsersChangePlanFreePlan,
                      ),
                    ),
                if (paidPlans.isNotEmpty) ...[
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: context.colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l.adminUsersChangePlanPaidNote(paidPlans.length),
                            style: context.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
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
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: (_selectedPlanId == null || _saving) ? null : _onSubmit,
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
    final l = context.l10n;
    if (_selectedPlanId == null) return;
    setState(() {
      _saving = true;
      _errorMsg = null;
    });
    try {
      await ref.read(adminUsersDataSourceProvider).changePlanFree(
            userId: widget.userId,
            planId: _selectedPlanId!,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = l.adminUsersChangePlanError;
        _saving = false;
      });
    }
  }
}
