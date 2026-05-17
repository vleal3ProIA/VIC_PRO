import 'package:flutter/material.dart';

import 'package:myapp/core/theme/app_tokens.dart';

/// Loading state genérico: `CircularProgressIndicator` centrado, opcio-
/// nalmente con un mensaje debajo.
///
/// Reemplaza el patrón `Center(child: CircularProgressIndicator())` que
/// aparece en ~20 sitios. Si quieres skeleton placeholders en el futuro,
/// se añaden aquí sin tocar callers.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({this.message, super.key});

  /// Mensaje opcional debajo del spinner ("Loading invoices…").
  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            AppSpacing.gapSm,
            Text(
              message!,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
