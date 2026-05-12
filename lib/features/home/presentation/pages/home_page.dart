import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/welcome/presentation/widgets/language_picker.dart';
import 'package:myapp/features/welcome/presentation/widgets/theme_toggle.dart';

/// Zona privada placeholder. Muestra el nombre del usuario, su email y un
/// botón de logout. Lo ampliaremos con el panel de ajustes (idioma + tema
/// persistente en BD) y el cambio de password en el siguiente paso.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final l = context.l10n;
    final displayName =
        (user?.userMetadata?['display_name'] as String?) ??
            (user?.userMetadata?['username'] as String?) ??
            user?.email?.split('@').first ??
            'user';

    return Scaffold(
      appBar: AppBar(
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
            tooltip: l.actionSignOut,
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) {
                context.goNamed(RouteNames.welcome);
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: context.colors.primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    size: 48,
                    color: context.colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l.homeWelcomeUser(displayName),
                  textAlign: TextAlign.center,
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (user?.email != null)
                  Text(
                    l.homeSignedInAs(user!.email!),
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 32),
                Text(
                  l.homePlaceholder,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
