import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

enum InfoBannerKind { info, success, warning }

/// Banner informativo discreto para avisos contextuales dentro de las
/// pantallas (p. ej. "usa solo el código, no pulses el botón del email").
/// No reemplaza errores — los errores usan `GeneralErrorSlot`.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    required this.message,
    super.key,
    this.kind = InfoBannerKind.info,
  });

  final String message;
  final InfoBannerKind kind;

  ({Color bg, Color fg, IconData icon}) _palette(BuildContext context) {
    return switch (kind) {
      InfoBannerKind.info => (
          bg: context.colors.primaryContainer.withValues(alpha: 0.5),
          fg: context.colors.onPrimaryContainer,
          icon: Icons.info_outline,
        ),
      InfoBannerKind.success => (
          bg: context.colors.tertiaryContainer.withValues(alpha: 0.5),
          fg: context.colors.onTertiaryContainer,
          icon: Icons.check_circle_outline,
        ),
      InfoBannerKind.warning => (
          bg: context.colors.errorContainer.withValues(alpha: 0.3),
          fg: context.colors.onErrorContainer,
          icon: Icons.warning_amber_outlined,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(palette.icon, size: 18, color: palette.fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: context.textTheme.bodySmall?.copyWith(
                color: palette.fg,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
