import 'package:flutter/material.dart';

/// Helper estático para mostrar dialogs de confirmación tipo
/// "¿Continuar con la acción X?". Centraliza el patrón `showDialog<bool>
/// + AlertDialog + [Cancel, Confirm]` que aparece en 12+ sitios.
///
/// Uso típico:
///
/// ```dart
/// final ok = await AppConfirmDialog.show(
///   context,
///   title: l.deleteAccountConfirmTitle,
///   body: l.deleteAccountConfirmBody,
///   confirmLabel: l.actionDeleteAccount,
///   danger: true,
/// );
/// if (ok != true) return;
/// // ... ejecutar la acción
/// ```
///
/// Devuelve `true` si el usuario confirma, `false` si cancela, `null`
/// si cierra el dialog (tap fuera / ESC). Los callers típicamente
/// chequean `if (ok != true) return;` que cubre los 3 casos.
class AppConfirmDialog {
  AppConfirmDialog._();

  /// Muestra un dialog modal y resuelve cuando el usuario decide.
  ///
  /// - [danger]: cuando es `true`, el botón de confirmar usa colores de
  ///   error (rojo) para señalar que la acción es destructiva (borrar,
  ///   cancelar suscripción, revocar acceso, etc.).
  /// - [cancelLabel]: si no se pasa, usa el "Cancel" localizado de
  ///   MaterialLocalizations — funciona en los 8 idiomas sin meter una
  ///   key i18n extra por cada caller.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    String? cancelLabel,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final cancel = cancelLabel ??
            MaterialLocalizations.of(ctx).cancelButtonLabel;
        final confirmButton = danger
            ? FilledButton.tonal(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                ),
                child: Text(confirmLabel),
              )
            : FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              );
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancel),
            ),
            confirmButton,
          ],
        );
      },
    );
  }
}
