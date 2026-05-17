import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../domain/changelog_entry.dart';

/// Visuales asociados a una categoría de changelog. Centralizados para
/// que la página user y la admin compartan los mismos iconos/colores.
class ChangelogCategoryVisuals {
  const ChangelogCategoryVisuals({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String Function(AppLocalizations) label;
}

ChangelogCategoryVisuals visualsFor(
  BuildContext context,
  ChangelogCategory category,
) {
  switch (category) {
    case ChangelogCategory.feature:
      return ChangelogCategoryVisuals(
        icon: Icons.auto_awesome_outlined,
        color: context.colors.primary,
        label: (l) => l.changelogCategoryFeature,
      );
    case ChangelogCategory.improvement:
      return ChangelogCategoryVisuals(
        icon: Icons.tune,
        color: context.colors.tertiary,
        label: (l) => l.changelogCategoryImprovement,
      );
    case ChangelogCategory.fix:
      return ChangelogCategoryVisuals(
        icon: Icons.bug_report_outlined,
        color: Colors.amber.shade800,
        label: (l) => l.changelogCategoryFix,
      );
    case ChangelogCategory.security:
      return ChangelogCategoryVisuals(
        icon: Icons.security_outlined,
        color: context.colors.error,
        label: (l) => l.changelogCategorySecurity,
      );
  }
}
