import 'package:flutter/material.dart';

import 'package:myapp/core/theme/app_tokens.dart';

/// Empty state genérico para listas/secciones sin contenido. Centraliza
/// el patrón "icono + título corto + mensaje secundario + acción
/// opcional" que antes vivía como `_Empty`/`_EmptyBox`/`_EmptyState`
/// duplicado en 4+ pantallas.
///
/// Uso típico:
///
/// ```dart
/// AppEmptyState(
///   icon: Icons.local_offer_outlined,
///   message: l.adminCouponsEmpty,
/// )
///
/// AppEmptyState(
///   icon: Icons.inbox_outlined,
///   title: l.notificationsEmptyTitle,
///   message: l.notificationsEmptyHint,
///   action: FilledButton.icon(...),
/// )
/// ```
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.title,
    this.action,
    this.iconSize = 48,
    super.key,
  });

  /// Icono representativo. Default `inbox_outlined` — neutro.
  final IconData icon;

  /// Línea principal (opcional). Si `null`, solo se muestra `message`.
  final String? title;

  /// Mensaje secundario. Si no hay `title`, este es el único texto.
  final String message;

  /// Botón / acción opcional debajo del mensaje (ej. "Crear el primero").
  final Widget? action;

  /// Tamaño del icono. Default 48 — suficiente para listas medianas.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: AppSpacing.paddingLg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: scheme.onSurfaceVariant),
          AppSpacing.gapSm,
          if (title != null) ...[
            Text(
              title!,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            AppSpacing.gapXs,
          ],
          Text(
            message,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            AppSpacing.gapMd,
            action!,
          ],
        ],
      ),
    );
  }
}
