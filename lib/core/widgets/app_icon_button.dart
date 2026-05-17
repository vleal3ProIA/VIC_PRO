import 'package:flutter/material.dart';

/// Wrapper de `IconButton` que **obliga** a pasar `tooltip` en
/// compile-time. El Material `IconButton` acepta `tooltip` opcional, lo
/// cual permite olvidar añadirlo y dejar un botón invisible para los
/// lectores de pantalla. Este widget cierra esa puerta:
/// `AppIconButton(tooltip: 'foo', icon: ..., onPressed: ...)`.
///
/// **Migración**: en archivos nuevos usa `AppIconButton`. Los `IconButton`
/// de Material existentes siguen funcionando — no es un breaking change.
/// La auditoría de 2.F.1 ya añadió tooltip a todos los actuales, así que
/// el codebase está limpio; este wrapper previene regresiones futuras.
///
/// Soporta los mismos params que el IconButton estándar excepto que:
/// - `tooltip` es **requerido** (compile-time).
/// - `onPressed` puede ser null (deshabilita el botón como el original).
/// - Para variantes filled/tonal/outlined, hay constructores nombrados
///   `AppIconButton.filled`, `.filledTonal`, `.outlined`.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize,
    this.color,
    this.style,
    super.key,
  }) : _variant = _Variant.standard;

  const AppIconButton.filled({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize,
    this.color,
    this.style,
    super.key,
  }) : _variant = _Variant.filled;

  const AppIconButton.filledTonal({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize,
    this.color,
    this.style,
    super.key,
  }) : _variant = _Variant.filledTonal;

  const AppIconButton.outlined({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize,
    this.color,
    this.style,
    super.key,
  }) : _variant = _Variant.outlined;

  /// Texto descriptivo del botón. Aparece como tooltip al hover y como
  /// label semántico para lectores de pantalla. Requerido — usar `''`
  /// si DE VERDAD no aplica (que casi nunca es el caso).
  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final double? iconSize;
  final Color? color;
  final ButtonStyle? style;

  final _Variant _variant;

  @override
  Widget build(BuildContext context) {
    switch (_variant) {
      case _Variant.standard:
        return IconButton(
          tooltip: tooltip,
          icon: icon,
          onPressed: onPressed,
          iconSize: iconSize,
          color: color,
          style: style,
        );
      case _Variant.filled:
        return IconButton.filled(
          tooltip: tooltip,
          icon: icon,
          onPressed: onPressed,
          iconSize: iconSize,
          color: color,
          style: style,
        );
      case _Variant.filledTonal:
        return IconButton.filledTonal(
          tooltip: tooltip,
          icon: icon,
          onPressed: onPressed,
          iconSize: iconSize,
          color: color,
          style: style,
        );
      case _Variant.outlined:
        return IconButton.outlined(
          tooltip: tooltip,
          icon: icon,
          onPressed: onPressed,
          iconSize: iconSize,
          color: color,
          style: style,
        );
    }
  }
}

enum _Variant { standard, filled, filledTonal, outlined }
