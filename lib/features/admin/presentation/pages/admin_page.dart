import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/account/application/profile_providers.dart';

/// Área de administración — destino del shell visible solo para `admin`.
///
/// El acceso está protegido por partida doble: el guard del router redirige
/// a `/home` si el usuario no es admin, y el destino ni siquiera aparece en
/// la navegación para no-admins. De momento es un placeholder; aquí irán la
/// gestión de usuarios, etc.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final role = ref.watch(currentRoleProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 32,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l.adminTitle,
                    style: context.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l.adminSubtitle,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.verified_user_outlined,
                    color: context.colors.tertiary,
                  ),
                  title: Text(l.adminRoleBadge),
                  subtitle: Text(role.name),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.toggle_on_outlined),
                  title: Text(l.adminFlagsTitle),
                  subtitle: Text(l.adminFlagsHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.adminFlags),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l.adminPlaceholder,
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
