import 'package:flutter/material.dart';

import 'package:myapp/core/theme/app_tokens.dart';

/// Error state genérico para pantallas que fallan al cargar.
/// Centraliza el patrón "icono error + mensaje + (botón Retry)" que
/// antes vivía como `Center(child: Text(... color: error))` inline.
///
/// Uso típico (con un FutureProvider Riverpod):
///
/// ```dart
/// async.when(
///   loading: () => const AppLoadingState(),
///   error: (e, _) => AppErrorState(
///     message: l.invoicesLoadError,
///     onRetry: () => ref.invalidate(invoicesProvider),
///   ),
///   data: (rows) => ...,
/// )
/// ```
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.message,
    this.detail,
    this.onRetry,
    this.retryLabel,
    this.icon = Icons.error_outline,
    super.key,
  });

  final String message;

  /// Detalle técnico opcional. Solo aparece si no es null/vacío.
  /// Se renderiza en bodySmall + onSurfaceVariant para ser discreto.
  final String? detail;

  /// Si se provee, aparece un botón debajo del mensaje.
  final VoidCallback? onRetry;

  /// Label del botón retry. Si null y `onRetry` no-null, usa "Retry"
  /// (en inglés — los callers que quieran localizado le pasan el suyo
  /// via [retryLabel]).
  final String? retryLabel;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final showDetail = detail != null && detail!.trim().isNotEmpty;
    return Padding(
      padding: AppSpacing.paddingLg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.error),
          AppSpacing.gapSm,
          Text(
            message,
            style: text.titleMedium?.copyWith(color: scheme.error),
            textAlign: TextAlign.center,
          ),
          if (showDetail) ...[
            AppSpacing.gapXs,
            Text(
              detail!,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (onRetry != null) ...[
            AppSpacing.gapMd,
            FilledButton.tonalIcon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(retryLabel ?? 'Retry'),
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
