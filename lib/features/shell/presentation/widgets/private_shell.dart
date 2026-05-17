import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/branding/application/branding_providers.dart';
import 'package:myapp/features/help/presentation/widgets/help_menu_button.dart';
import 'package:myapp/features/notifications/presentation/widgets/notification_bell.dart';
import 'package:myapp/features/search/presentation/widgets/cmd_k_shortcut.dart';
import 'package:myapp/features/search/presentation/widgets/search_button.dart';
import 'package:myapp/features/shell/presentation/widgets/skip_to_content_link.dart';
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
class PrivateShell extends ConsumerStatefulWidget {
  const PrivateShell({
    required this.location,
    required this.child,
    super.key,
  });

  /// Ruta actual (`state.uri.path`) — para resaltar el destino activo.
  final String location;
  final Widget child;

  @override
  ConsumerState<PrivateShell> createState() => _PrivateShellState();
}

class _PrivateShellState extends ConsumerState<PrivateShell> {
  /// Destino del skip-to-content link. Lo coloco en el `body` del
  /// Scaffold para que la activación del skip-link mueva el foco
  /// directamente al primer elemento del contenido principal,
  /// saltándose el AppBar (LanguagePicker/ThemeToggle/Avatar) y el
  /// NavigationRail/Drawer.
  late final FocusNode _mainContentFocus =
      FocusNode(debugLabel: 'private-shell-main-content', skipTraversal: true);

  @override
  void dispose() {
    _mainContentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isAdmin = ref.watch(isAdminProvider);
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
      // El destino de administración solo aparece para admins. Aunque
      // alguien forzara la ruta, el guard del router lo redirige.
      if (isAdmin)
        _Destination(
          path: RoutePaths.admin,
          routeName: RouteNames.admin,
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings,
          label: l.navAdmin,
        ),
    ];

    var selectedIndex =
        destinations.indexWhere((d) => widget.location == d.path);
    if (selectedIndex < 0) selectedIndex = 0;

    void goTo(int index) {
      context.goNamed(destinations[index].routeName);
    }

    final isWide = !context.isMobile;

    // El body se envuelve en Focus + FocusTraversalGroup para que el
    // skip-link (debajo del Stack) pueda mover el foco aquí saltándose
    // el AppBar y la navegación.
    Widget wrapBody(Widget body) => FocusTraversalGroup(
          child: Focus(
            focusNode: _mainContentFocus,
            // skipTraversal=true ya está en el FocusNode -> el propio
            // Focus widget no se "ve" en el orden de Tab, solo sirve
            // como destino programático para requestFocus().
            child: body,
          ),
        );

    return CmdKShortcut(
      child: Stack(
        children: [
          Scaffold(
          appBar: AppBar(
            scrolledUnderElevation: 0,
            title: Text(
              ref.watch(brandingOrFallbackProvider).commercialName,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: const [
              SearchButton(),
              NotificationBell(),
              HelpMenuButton(),
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
                      commercialName: ref
                          .watch(brandingOrFallbackProvider)
                          .commercialName,
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
                    Expanded(child: wrapBody(widget.child)),
                  ],
                )
              : wrapBody(widget.child),
        ),
        // Skip-to-content link: invisible salvo cuando recibe foco.
        // Por estar sobre el Stack, queda por encima del AppBar.
          SkipToContentLink(targetFocusNode: _mainContentFocus),
        ],
      ),
    );
  }
}

/// Lista de navegación usada dentro del `Drawer` en móvil.
class _NavList extends StatelessWidget {
  const _NavList({
    required this.destinations,
    required this.selectedIndex,
    required this.commercialName,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final String commercialName;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Text(
            commercialName,
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
