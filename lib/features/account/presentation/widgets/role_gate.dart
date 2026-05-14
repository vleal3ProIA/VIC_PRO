import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/domain/entities/user_role.dart';

/// Muestra [child] solo si el rol del usuario actual está en [allowed]; en
/// caso contrario muestra [fallback] (por defecto, nada).
///
/// Para proteger COMPONENTES por rol (botones, secciones, items de menú…).
/// La protección de RUTAS la hace el guard del router.
///
/// ```dart
/// RoleGate.admin(child: AdminPanelButton());
/// ```
class RoleGate extends ConsumerWidget {
  const RoleGate({
    required this.child,
    this.allowed = const {UserRole.admin},
    this.fallback = const SizedBox.shrink(),
    super.key,
  });

  /// Atajo para "solo administradores".
  const RoleGate.admin({
    required this.child,
    this.fallback = const SizedBox.shrink(),
    super.key,
  }) : allowed = const {UserRole.admin};

  final Widget child;
  final Set<UserRole> allowed;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentRoleProvider);
    return allowed.contains(role) ? child : fallback;
  }
}
