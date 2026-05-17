import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../domain/broadcast.dart';

class BroadcastStatusChip extends StatelessWidget {
  const BroadcastStatusChip({required this.status, super.key});
  final BroadcastStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (icon, color, label) = switch (status) {
      BroadcastStatus.draft => (
          Icons.edit_outlined,
          context.colors.onSurfaceVariant,
          l.broadcastsStatusDraft,
        ),
      BroadcastStatus.sending => (
          Icons.send_outlined,
          Colors.amber.shade800,
          l.broadcastsStatusSending,
        ),
      BroadcastStatus.sent => (
          Icons.check_circle,
          context.colors.primary,
          l.broadcastsStatusSent,
        ),
      BroadcastStatus.failed => (
          Icons.error,
          context.colors.error,
          l.broadcastsStatusFailed,
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
