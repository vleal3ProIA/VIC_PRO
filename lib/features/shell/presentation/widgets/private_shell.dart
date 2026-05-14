import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/shell/presentation/widgets/user_avatar_menu.dart';
import 'package:myapp/features/welcome/presentation/widgets/language_picker.dart';
import 'package:myapp/features/welcome/presentation/widgets/theme_toggle.dart';

/// Destino de navegación de la zona privada.
class _Destination {
  const _Destination({
    required this.path,
    required this.routeName,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final String path;
  final String routeName;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Shell de la zona privada (área autenticada).
///
/// Aporta el cromo común a todas las páginas privadas: cabecera con
/// idioma/tema/avatar y navegación lateral. Responsive:
/// - móvil  → `Drawer` con hamburguesa.
/// - ancho  → `NavigationRail` fijo a la izquierda.
///
/// Se monta vía `ShellRoute`, así que persiste al navegar entre destinos.
class PrivateShell extends StatelessWidget {
  const PrivateShell({
    required this.location,
    required this.child,
    super.key,
  });

  /// Ruta actual (`state.uri.path`) — para resaltar el destino activo.
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final destinations = <_Destination>[
      _Destination(
        path: RoutePaths.home,
        routeName: RouteNames.home,
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: l.navDashboard,
      ),
      _Destination(
        path: RoutePaths.accountSettings,
        routeName: RouteNames.accountSettings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: l.navSettings,
      ),
    ];

    var selectedIndex = destinations.indexWhere((d) => location == d.path);
    if (selectedIndex < 0) selectedIndex = 0;

    void goTo(int index) {
      context.goNamed(destinations[index].routeName);
    }

    final isWide = !context.isMobile;

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: Text(
          context.l10n.appTitle,
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: const [
          LanguagePicker(),
          ThemeToggle(),
          SizedBox(width: 4),
          UserAvatarMenu(),
          SizedBox(width: 8),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: _NavList(
                  destinations: destinations,
                  selectedIndex: selectedIndex,
                  onSelected: (i) {
                    Navigator.of(context).pop(); // cierra el drawer
                    goTo(i);
                  },
                ),
              ),
            ),
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: goTo,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            )
          : child,
    );
  }
}

/// Lista de navegación usada dentro del `Drawer` en móvil.
class _NavList extends StatelessWidget {
  const _NavList({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Text(
            context.l10n.appTitle,
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        for (var i = 0; i < destinations.length; i++)
          ListTile(
            leading: Icon(
              i == selectedIndex
                  ? destinations[i].selectedIcon
                  : destinations[i].icon,
            ),
            title: Text(destinations[i].label),
            selected: i == selectedIndex,
            onTap: () => onSelected(i),
          ),
      ],
    );
  }
}
