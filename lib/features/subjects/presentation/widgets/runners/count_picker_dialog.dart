// ============================================================================
// subjects · CountPickerDialog
// ----------------------------------------------------------------------------
// Modal con presets 10/25/50/75/100/TODAS para elegir cuantas preguntas
// realizar al pulsar "Empezar test". El selector se movio AQUI desde el
// configurador de cada panel (test / V-F): "siempre generamos el maximo;
// solo modificamos el numero cuando vayamos a realizar el test".
//
// Devuelve un `int`: 0 = TODAS, o el numero elegido. `null` = cancelado.
// Si [available] es menor que un preset, ese preset se atenua. "TODAS"
// siempre esta disponible (usa el total).
// ============================================================================

import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';

class _CountOption {
  const _CountOption(this.value);
  final int value; // 0 = TODAS
}

/// Presets fijos. 0 representa "TODAS".
const _kPresets = <_CountOption>[
  _CountOption(10),
  _CountOption(25),
  _CountOption(50),
  _CountOption(75),
  _CountOption(100),
  _CountOption(0),
];

/// Abre el selector de cantidad de preguntas. Devuelve:
///   - un `int >= 1` con la cantidad elegida (limitada al pool real).
///   - `0` si eligio "TODAS".
///   - `null` si cancelo.
///
/// [available] es el numero real de preguntas disponibles; se usa para
/// atenuar presets > available y mostrar el badge "TODAS = N".
Future<int?> showCountPickerDialog(
  BuildContext context, {
  required int available,
}) {
  return showDialog<int>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _CountPickerDialog(available: available),
  );
}

class _CountPickerDialog extends StatelessWidget {
  const _CountPickerDialog({required this.available});

  final int available;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    return AlertDialog(
      title: Text(l.studyTestCount),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.studyTestBank(available),
              style: context.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final p in _kPresets)
                  _ChipButton(option: p, available: available),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l.actionCancel),
        ),
      ],
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.option, required this.available});

  final _CountOption option;
  final int available;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final enabled = option.value == 0 || option.value <= available;
    final label = option.value == 0
        ? '${l.studyTestAllQuestions} ($available)'
        : '${option.value}';
    return FilledButton.tonal(
      onPressed:
          enabled ? () => Navigator.of(context).pop(option.value) : null,
      child: Text(label),
    );
  }
}
