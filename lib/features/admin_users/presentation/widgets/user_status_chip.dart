import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../domain/admin_user.dart';

/// Chip pequeño con icono + color por estado, reutilizado en la tabla
/// y en el detalle.
class UserStatusChip extends StatelessWidget {
  const UserStatusChip({required this.status, super.key});
  final UserStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (icon, color, label) = switch (status) {
      UserStatus.active => (
          Icons.check_circle,
          context.colors.primary,
          l.adminUsersStatusActive,
        ),
      UserStatus.blocked => (
          Icons.timer_outlined,
          Colors.amber.shade800,
          l.adminUsersStatusBlocked,
        ),
      UserStatus.deactivated => (
          Icons.block,
          context.colors.error,
          l.adminUsersStatusDeactivated,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
