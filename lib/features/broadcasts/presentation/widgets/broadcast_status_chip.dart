import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/premium/premium_badge.dart';

import '../../domain/broadcast.dart';

/// Chip de status para un broadcast. Wrapper de `PremiumBadge` con
/// mapeo (status -> variant + icon + label localizado). Lo usan la
/// lista y la detail page.
class BroadcastStatusChip extends StatelessWidget {
  const BroadcastStatusChip({required this.status, super.key});
  final BroadcastStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (variant, icon, label) = switch (status) {
      BroadcastStatus.draft => (
          PremiumBadgeVariant.neutral,
          Icons.edit_outlined,
          l.broadcastsStatusDraft,
        ),
      BroadcastStatus.sending => (
          PremiumBadgeVariant.warning,
          Icons.send_outlined,
          l.broadcastsStatusSending,
        ),
      BroadcastStatus.sent => (
          PremiumBadgeVariant.success,
          Icons.check_circle,
          l.broadcastsStatusSent,
        ),
      BroadcastStatus.failed => (
          PremiumBadgeVariant.error,
          Icons.error,
          l.broadcastsStatusFailed,
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
