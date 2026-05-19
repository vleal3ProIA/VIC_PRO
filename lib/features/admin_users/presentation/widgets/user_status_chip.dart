import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/premium/premium_badge.dart';

import '../../domain/admin_user.dart';

/// Chip pequeño con icono + variant por estado, reutilizado en la
/// tabla y en el detalle. Wrapper de `PremiumBadge` con mapeo
/// (status -> variant + icon + label localizado).
class UserStatusChip extends StatelessWidget {
  const UserStatusChip({required this.status, super.key});
  final UserStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (variant, icon, label) = switch (status) {
      UserStatus.active => (
          PremiumBadgeVariant.success,
          Icons.check_circle,
          l.adminUsersStatusActive,
        ),
      UserStatus.blocked => (
          PremiumBadgeVariant.warning,
          Icons.timer_outlined,
          l.adminUsersStatusBlocked,
        ),
      UserStatus.deactivated => (
          PremiumBadgeVariant.error,
          Icons.block,
          l.adminUsersStatusDeactivated,
        ),
    };
    return PremiumBadge(
      label: label,
      variant: variant,
      icon: icon,
      dense: true,
    );
  }
}
