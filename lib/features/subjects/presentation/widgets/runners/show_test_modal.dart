// ============================================================================
// subjects · Helper compartido para abrir un runner (Test / V-F / etc.) en un
// modal casi a pantalla completa, con el resto de la app difuminada y atenuada
// con el color del proyecto para no distraer.
//
// Extraído de `subject_study_panel.dart` para que tanto el Panel como las
// vistas inline de /mis-temarios/<id>/<kind> reutilicen el mismo `showGeneral
// Dialog` con la misma animación / blur, sin duplicar código.
// ============================================================================

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Abre [dialog] en un `showGeneralDialog` con barrera difuminada (blur) y
/// atenuada con la superficie del tema actual. Devuelve cuando el dialog se
/// cierra.
Future<void> showTestModal(BuildContext context, Widget dialog) {
  final scheme = Theme.of(context).colorScheme;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => dialog,
    transitionBuilder: (_, anim, __, child) {
      final t = Curves.easeOut.transform(anim.value);
      return Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8 * t, sigmaY: 8 * t),
              child: ColoredBox(
                color: scheme.surface.withValues(alpha: 0.72 * t),
              ),
            ),
          ),
          Opacity(opacity: t, child: child),
        ],
      );
    },
  );
}
