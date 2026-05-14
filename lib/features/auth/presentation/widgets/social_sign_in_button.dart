import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Botón outlined para login social (Google, Apple, …).
///
/// Mantiene la misma altura (48) que el resto de botones del formulario de
/// auth para no romper el tamaño fijo de la card. Acepta un asset SVG como
/// icono y un estado [busy] que muestra un spinner.
class SocialSignInButton extends StatelessWidget {
  const SocialSignInButton({
    required this.label,
    required this.iconAsset,
    required this.onPressed,
    super.key,
    this.busy = false,
    this.iconColor,
  });

  /// Texto del botón (p. ej. "Continuar con Google").
  final String label;

  /// Ruta del asset SVG del logo (p. ej. `assets/icons/google.svg`).
  final String iconAsset;

  /// `null` deshabilita el botón.
  final VoidCallback? onPressed;

  /// Muestra un spinner en lugar del logo.
  final bool busy;

  /// Si se indica, tiñe el logo con este color (útil para logos monocromos
  /// como el de Apple, que debe seguir el tema). Si es `null` el SVG se
  /// dibuja con sus colores originales (p. ej. la "G" multicolor de Google).
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
      icon: busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : SvgPicture.asset(
              iconAsset,
              height: 18,
              width: 18,
              semanticsLabel: label,
              colorFilter: iconColor == null
                  ? null
                  : ColorFilter.mode(iconColor!, BlendMode.srcIn),
            ),
      label: Text(label),
    );
  }
}
