import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/welcome/presentation/widgets/language_picker.dart';
import 'package:myapp/features/welcome/presentation/widgets/theme_toggle.dart';

/// Barra superior pública (sin usuario logado): idioma · tema · entrar.
class PublicTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PublicTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Text(
        context.l10n.appTitle,
        style: context.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        const LanguagePicker(),
        const ThemeToggle(),
        IconButton(
          tooltip: context.l10n.signInTooltip,
          icon: const Icon(Icons.login),
          onPressed: () => context.goNamed(RouteNames.login),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
