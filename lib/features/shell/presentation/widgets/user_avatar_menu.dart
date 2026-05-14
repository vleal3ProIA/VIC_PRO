import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/presentation/widgets/user_avatar.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';

enum _AvatarAction { settings, signOut }

/// Avatar del usuario en la cabecera, con menú: Ajustes · Cerrar sesión.
///
/// Por ahora muestra la inicial del nombre; cuando exista la subida de
/// avatar (Fase 8) mostrará la imagen.
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

    return PopupMenuButton<_AvatarAction>(
      tooltip: name,
      offset: const Offset(0, 48),
      onSelected: (action) async {
        switch (action) {
          case _AvatarAction.settings:
            context.goNamed(RouteNames.accountSettings);
          case _AvatarAction.signOut:
            await ref.read(authRepositoryProvider).signOut();
            if (context.mounted) context.goNamed(RouteNames.welcome);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_AvatarAction>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (email.isNotEmpty)
                Text(
                  email,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_AvatarAction>(
          value: _AvatarAction.settings,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: Text(l.navSettings),
          ),
        ),
        PopupMenuItem<_AvatarAction>(
          value: _AvatarAction.signOut,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: context.colors.error),
            title: Text(
              l.actionSignOut,
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ),
      ],
      child: UserAvatar(name: name, avatarUrl: avatarUrl, radius: 16),
    );
  }
}
