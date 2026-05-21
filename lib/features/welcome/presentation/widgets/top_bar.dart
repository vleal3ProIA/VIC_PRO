import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/welcome/presentation/widgets/language_picker.dart';
import 'package:myapp/features/welcome/presentation/widgets/theme_toggle.dart';

/// Barra superior pública: idioma · tema · entrar / ir a la app.
///
/// El último icono es **consciente de la sesión**:
///   - SIN sesión  → icono "login" que lleva a `/login`.
///   - CON sesión  → icono "dashboard" que lleva a `/home` (antes mostraba
///     "login" y al pulsarlo el guard `publicOnly` te reenviaba a `/home`,
///     lo que parecía un "auto-login" confuso).
class PublicTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const PublicTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(isAuthenticatedProvider);

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
        if (authed)
          IconButton(
            tooltip: context.l10n.navDashboard,
            icon: const Icon(Icons.space_dashboard_outlined),
            onPressed: () => context.goNamed(RouteNames.home),
          )
        else
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
