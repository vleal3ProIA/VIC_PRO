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
import 'package:myapp/features/status/presentation/widgets/maintenance_banner.dart';

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

/// Ancho del sidebar lateral expandido (zona privada, pantallas anchas).
const double _kSidebarWidth = 256;

/// Shell de la zona privada (área autenticada).
///
/// Aporta el cromo común a todas las páginas privadas:
/// - **Header**: logo + botón para plegar/desplegar el sidebar a la izquierda;
///   búsqueda, notificaciones, ayuda y avatar a la derecha.
/// - **Sidebar lateral** ancho y plegable (ancho) o `Drawer` (móvil).
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Sidebar visible en pantallas anchas. El botón ☰ del header lo togglea.
  bool _sidebarExpanded = true;

  /// Destino del skip-to-content link. Lo coloco en el `body` del Scaffold
  /// para que la activación del skip-link mueva el foco directamente al
  /// primer elemento del contenido principal, saltándose el AppBar y el
  /// sidebar.
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
    final commercialName = ref.watch(brandingOrFallbackProvider).commercialName;

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

    // Botón ☰: en ancho pliega/despliega el sidebar; en móvil abre el Drawer.
    void onToggleSidebar() {
      if (isWide) {
        setState(() => _sidebarExpanded = !_sidebarExpanded);
      } else {
        _scaffoldKey.currentState?.openDrawer();
      }
    }

    // El body se envuelve en Focus + FocusTraversalGroup para que el
    // skip-link (debajo del Stack) pueda mover el foco aquí saltándose
    // el AppBar y la navegación.
    Widget wrapBody(Widget body) => FocusTraversalGroup(
          child: Focus(
            focusNode: _mainContentFocus,
            child: body,
          ),
        );

    return CmdKShortcut(
      child: Stack(
        children: [
          Scaffold(
            key: _scaffoldKey,
            appBar: AppBar(
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing: 12,
              // ─── Izquierda: logo + botón de sidebar ───
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      commercialName,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).openAppDrawerTooltip,
                    icon: Icon(
                      isWide && !_sidebarExpanded
                          ? Icons.menu
                          : Icons.menu_open,
                    ),
                    onPressed: onToggleSidebar,
                  ),
                ],
              ),
              // ─── Derecha: búsqueda · campana · ayuda · avatar ───
              actions: const [
                SearchButton(),
                NotificationBell(),
                HelpMenuButton(),
                SizedBox(width: 4),
                UserAvatarMenu(),
                SizedBox(width: 8),
              ],
            ),
            drawer: isWide
                ? null
                : Drawer(
                    child: SafeArea(
                      child: _SidebarNav(
                        destinations: destinations,
                        selectedIndex: selectedIndex,
                        commercialName: commercialName,
                        showHeader: true,
                        onSelected: (i) {
                          Navigator.of(context).pop(); // cierra el drawer
                          goTo(i);
                        },
                      ),
                    ),
                  ),
            body: Column(
              children: [
                // Banner de incidente activo (auto-oculto si no aplica).
                const MaintenanceBanner(),
                Expanded(
                  child: isWide
                      ? Row(
                          children: [
                            if (_sidebarExpanded) ...[
                              SizedBox(
                                width: _kSidebarWidth,
                                child: _SidebarNav(
                                  destinations: destinations,
                                  selectedIndex: selectedIndex,
                                  commercialName: commercialName,
                                  showHeader: false,
                                  onSelected: goTo,
                                ),
                              ),
                              const VerticalDivider(width: 1),
                            ],
                            Expanded(child: wrapBody(widget.child)),
                          ],
                        )
                      : wrapBody(widget.child),
                ),
              ],
            ),
          ),
          // Skip-to-content link: invisible salvo cuando recibe foco.
          SkipToContentLink(targetFocusNode: _mainContentFocus),
        ],
      ),
    );
  }
}

/// Lista de navegación lateral. Se usa tanto en el `Drawer` (móvil) como en
/// el sidebar fijo (ancho). [showHeader] muestra el nombre comercial arriba
/// (solo en el drawer; en ancho el nombre ya está en el AppBar).
class _SidebarNav extends StatelessWidget {
  const _SidebarNav({
    required this.destinations,
    required this.selectedIndex,
    required this.commercialName,
    required this.showHeader,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final String commercialName;
  final bool showHeader;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(
              commercialName,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        for (var i = 0; i < destinations.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              leading: Icon(
                i == selectedIndex
                    ? destinations[i].selectedIcon
                    : destinations[i].icon,
                size: 20,
              ),
              title: Text(
                destinations[i].label,
                style: context.textTheme.bodyMedium?.copyWith(
                  fontWeight:
                      i == selectedIndex ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              selected: i == selectedIndex,
              selectedTileColor: scheme.primary.withValues(alpha: 0.10),
              selectedColor: scheme.primary,
              onTap: () => onSelected(i),
            ),
          ),
      ],
    );
  }
}
