import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/theme_provider.dart';

/// Botón cíclico de tema: sistema → claro → oscuro → sistema...
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeNotifierProvider);
    final (icon, label) = switch (mode) {
      ThemeMode.system => (Icons.brightness_auto_outlined, context.l10n.themeSystem),
      ThemeMode.light => (Icons.light_mode_outlined, context.l10n.themeLight),
      ThemeMode.dark => (Icons.dark_mode_outlined, context.l10n.themeDark),
    };

    return IconButton(
      tooltip: '${context.l10n.themeSelectorTooltip} ($label)',
      icon: Icon(icon),
      onPressed: () => ref.read(themeNotifierProvider.notifier).cycle(),
    );
  }
}
