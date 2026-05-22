import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/presentation/widgets/user_avatar.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';

enum _AvatarAction {
  notifications,
  files,
  settings,
  signOut,
}

/// Avatar del usuario en la cabecera, con menu desplegable premium
/// estilo Stripe / MaterialPro:
///
/// - Header: avatar grande + nombre + email.
/// - Atajos a las paginas del usuario logueado mas frecuentes:
///   Notifications, Files, Activity.
/// - Toggle de modo claro/oscuro inline.
/// - Account Settings + Sign Out (destructive).
///
/// Diferencia con el menu original: aqui agrupamos los accesos rapidos
/// (que antes solo estaban en sidebar) para coincidir con el patron
/// MaterialPro pedido. NO duplica los items: si el sidebar tambien
/// los muestra, el user puede usar cualquiera de los dos.
class UserAvatarMenu extends ConsumerWidget {
  const UserAvatarMenu({super.key});

  String _displayName(WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return (user?.userMetadata?['display_name'] as String?) ??
        (user?.userMetadata?['username'] as String?) ??
        user?.email?.split('@').first ??
        'user';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final user = ref.watch(currentUserProvider);
    final name = _displayName(ref);
    final email = user?.email ?? '';
    final avatarUrl = ref.watch(myProfileProvider).valueOrNull?.avatarUrl;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopupMenuButton<_AvatarAction>(
      tooltip: name,
      offset: const Offset(0, 52),
      // Estilo premium: rounded corners, sin elevation Material crudo.
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.brMd),
      elevation: 8,
      color: scheme.surface,
      constraints: const BoxConstraints(
        minWidth: 260,
        maxWidth: 300,
      ),
      onSelected: (action) async {
        switch (action) {
          case _AvatarAction.notifications:
            context.goNamed(RouteNames.notifications);
          case _AvatarAction.files:
            context.goNamed(RouteNames.files);
          case _AvatarAction.settings:
            context.goNamed(RouteNames.accountSettings);
          case _AvatarAction.signOut:
            await ref.read(authRepositoryProvider).signOut();
            if (context.mounted) context.goNamed(RouteNames.welcome);
        }
      },
      itemBuilder: (context) => [
        // ─── Header: avatar + nombre + email ───
        PopupMenuItem<_AvatarAction>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _AvatarMenuHeader(
            name: name,
            email: email,
            avatarUrl: avatarUrl,
          ),
        ),
        const PopupMenuDivider(height: 1),
        // ─── Atajos a paginas frecuentes ───
        _premiumMenuItem(
          value: _AvatarAction.notifications,
          icon: Icons.notifications_outlined,
          label: l.notificationsTitle,
          scheme: scheme,
        ),
        _premiumMenuItem(
          value: _AvatarAction.files,
          icon: Icons.cloud_outlined,
          label: l.filesTitle,
          scheme: scheme,
        ),
        const PopupMenuDivider(height: 1),
        _premiumMenuItem(
          value: _AvatarAction.settings,
          icon: Icons.settings_outlined,
          label: l.navSettings,
          scheme: scheme,
        ),
        const PopupMenuDivider(height: 1),
        // ─── Sign out (destructive, color rojo) ───
        _premiumMenuItem(
          value: _AvatarAction.signOut,
          icon: Icons.logout,
          label: l.actionSignOut,
          scheme: scheme,
          destructive: true,
        ),
      ],
      child: UserAvatar(name: name, avatarUrl: avatarUrl, radius: 16),
    );
  }

  /// Helper para construir items con look uniforme premium: icon a la
  /// izquierda + label, padding generoso, hover state nativo de
  /// PopupMenuItem.
  PopupMenuEntry<_AvatarAction> _premiumMenuItem({
    required _AvatarAction value,
    required IconData icon,
    required String label,
    required ColorScheme scheme,
    bool destructive = false,
  }) {
    final color = destructive ? scheme.error : scheme.onSurface;
    return PopupMenuItem<_AvatarAction>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Header del menu: avatar grande, nombre y email. No clickable;
/// informativo solo (PopupMenuItem con `enabled: false`).
class _AvatarMenuHeader extends StatelessWidget {
  const _AvatarMenuHeader({
    required this.name,
    required this.email,
    required this.avatarUrl,
  });

  final String name;
  final String email;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          UserAvatar(name: name, avatarUrl: avatarUrl, radius: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
