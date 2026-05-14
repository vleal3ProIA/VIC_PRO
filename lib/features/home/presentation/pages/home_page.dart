import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';

/// Zona privada — destino "Dashboard" del shell. De momento es un placeholder
/// de bienvenida; las tarjetas/estadísticas llegarán con el dashboard.
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                l.homeWelcomeUser(displayName),
                style: context.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (user?.email != null) ...[
                const SizedBox(height: 4),
                Text(
                  l.homeSignedInAs(user!.email!),
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.dashboard_outlined,
                            color: context.colors.primary,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l.navDashboard,
                            style: context.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l.homePlaceholder,
                        style: context.textTheme.bodyLarge?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.shield_outlined,
                    color: context.colors.primary,
                  ),
                  title: Text(l.actionEnableMfa),
                  subtitle: Text(l.settingsSecurityHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.mfaSetup),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
