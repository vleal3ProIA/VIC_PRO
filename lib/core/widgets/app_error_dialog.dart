// ============================================================================
// AppErrorDialog · Modal central reutilizable para errores genericos (PR 0083)
// ----------------------------------------------------------------------------
// Sustituye los SnackBar de `content: Text(l.errorGeneric)` por un dialog
// modal centrado, responsive (max 480px en desktop, full-width con padding
// en mobile). Mas visible que un snackbar — ideal para fallos de operacion
// donde queremos que el user lea el mensaje y haga "OK" antes de seguir.
//
// Solo lo usamos para ERRORES genericos. Los snackbars de SUCCESS se quedan
// como estan (son mas discretos y no requieren atencion explicita).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

/// Muestra un dialog modal centrado con titulo + mensaje + boton OK.
/// Responsive: max 480px en desktop, full-width en mobile.
///
/// Devuelve un `Future<void>` que resuelve cuando el user pulsa OK o
/// cierra el dialog (tap fuera / ESC).
Future<void> showAppErrorDialog(
  BuildContext context, {
  String? customMessage,
}) async {
  final l = context.l10n;
  final message = customMessage ?? l.errorGeneric;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final media = MediaQuery.of(ctx);
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            // Permite ocupar todo el ancho disponible en mobile (con
            // padding del insetPadding ya descontado).
            minWidth: media.size.width < 480
                ? media.size.width - 48
                : 0,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: scheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  l.errorTitle,
                  style: Theme.of(ctx).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.actionOk),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
