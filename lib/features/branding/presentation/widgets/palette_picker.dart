import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../branding_palettes.dart';

/// Selector visual de paleta. Pinta un círculo de color por cada
/// [BrandingPalette] disponible; el seleccionado se marca con un
/// border + check.
class PalettePicker extends StatelessWidget {
  const PalettePicker({
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final p in BrandingPalettes.all)
          _PaletteSwatch(
            palette: p,
            isSelected: p.slug == selected,
            enabled: enabled,
            onTap: () => onSelected(p.slug),
          ),
      ],
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.palette,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final BrandingPalette palette;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: palette.label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: palette.previewColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? context.colors.onSurface
                  : Colors.transparent,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.previewColor.withValues(alpha: 0.3),
                blurRadius: isSelected ? 8 : 0,
                spreadRadius: isSelected ? 1 : 0,
              ),
            ],
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 26,
                  semanticLabel: palette.label,
                )
              : null,
        ),
      ),
    );
  }
}
