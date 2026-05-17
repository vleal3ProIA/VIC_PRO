import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/uploads_providers.dart';
import '../../domain/uploaded_file.dart';

/// Barra horizontal con el uso de storage del tenant actual. Muestra
/// "Usados X MB de Y GB" + bar visual (verde / ámbar al 85% / rojo al
/// llenarse). Si el tenant tiene cuota ilimitada, muestra solo el uso
/// sin barra de progreso.
///
/// Reusable: se mete en `/account-settings/files` y en cualquier
/// dialog de upload como contexto.
class StorageQuotaBar extends ConsumerWidget {
  const StorageQuotaBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(tenantStorageQuotaProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const SizedBox.shrink(),
      data: (q) => _QuotaBody(quota: q, l: l),
    );
  }
}

class _QuotaBody extends StatelessWidget {
  const _QuotaBody({required this.quota, required this.l});
  final StorageQuota quota;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final usedStr = formatBytes(quota.usedBytes);
    final quotaStr = quota.isUnlimited ? '∞' : formatBytes(quota.quotaBytes);
    final color = quota.isFull
        ? scheme.error
        : quota.isWarning
            ? Colors.amber.shade700
            : scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_outlined, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                quota.isUnlimited
                    ? l.storageUsedUnlimited(usedStr)
                    : l.storageUsedOf(usedStr, quotaStr),
                style: context.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (!quota.isUnlimited)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: quota.fraction,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
      ],
    );
  }
}

/// Formatea bytes humanamente: 124 B, 5.3 KB, 1.2 MB, 47 GB…
/// 1024-based (binary) — coherente con la mayoría de UIs de Storage.
String formatBytes(int bytes) {
  if (bytes < 0) return '∞';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIdx = 0;
  while (value >= 1024 && unitIdx < units.length - 1) {
    value /= 1024;
    unitIdx++;
  }
  final formatted = value >= 100
      ? value.toStringAsFixed(0)
      : value >= 10
          ? value.toStringAsFixed(1)
          : value.toStringAsFixed(2);
  return '$formatted ${units[unitIdx]}';
}
