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
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: Text(l.adminPlansTitle),
                  subtitle: Text(l.adminPlansHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.adminPlans),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: Text(l.adminBrandingTitle),
                  subtitle: Text(l.adminBrandingHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.adminBranding),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.local_offer_outlined),
                  title: Text(l.adminCouponsTitle),
                  subtitle: Text(l.adminCouponsHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.adminCoupons),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l.adminTrashTitle),
                  subtitle: Text(l.adminTrashHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.adminTrash),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text(l.adminChangelogTitle),
                  subtitle: Text(l.adminChangelogHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.adminChangelog),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.brush_outlined),
                  title: Text(l.adminAppBrandingTitle),
                  subtitle: Text(l.adminAppBrandingHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.adminAppBranding),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.mark_email_read_outlined),
                  title: Text(l.adminEmailLogTitle),
                  subtitle: Text(l.adminEmailLogHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.adminEmailLog),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(l.adminUsersTitle),
                  subtitle: Text(l.adminUsersHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed(RouteNames.adminUsers),
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
