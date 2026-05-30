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

/// Ancho del sidebar lateral expandido (zona privada, pantallas anchas).
const double _kSidebarWidth = 256;

/// Shell de la zona privada (área autenticada).
///
/// - **Header**: logo + botón para plegar/desplegar el sidebar a la izquierda;
///   búsqueda, notificaciones, ayuda y avatar a la derecha.
/// - **Sidebar lateral** ancho y plegable (ancho) o `Drawer` (móvil), con
///   navegación: Panel, Ajustes (submenú: Cuenta/Workspace/Facturación/
///   Seguridad) y Administración (solo admin).
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

  late final FocusNode _mainContentFocus =
      FocusNode(debugLabel: 'private-shell-main-content', skipTraversal: true);

  @override
  void dispose() {
    _mainContentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final commercialName = ref.watch(brandingOrFallbackProvider).commercialName;
    final section =
        GoRouterState.of(context).uri.queryParameters['section'] ?? 'account';

    final isWide = !context.isMobile;

    void onToggleSidebar() {
      if (isWide) {
        setState(() => _sidebarExpanded = !_sidebarExpanded);
      } else {
        _scaffoldKey.currentState?.openDrawer();
      }
    }

    // Navega y, en móvil (drawer abierto), lo cierra primero.
    void navigate(VoidCallback go) {
      if (!isWide) Navigator.of(context).maybePop();
      go();
    }

    Widget buildNav({required bool showHeader}) => _SidebarNav(
          location: widget.location,
          section: section,
          isAdmin: isAdmin,
          commercialName: commercialName,
          showHeader: showHeader,
          onGoHome: () => navigate(() => context.goNamed(RouteNames.home)),
          onGoMyMaterial: () =>
              navigate(() => context.goNamed(RouteNames.myMaterial)),
          onGoSettings: (s) => navigate(
            () => context.goNamed(
              RouteNames.accountSettings,
              queryParameters: {'section': s},
            ),
          ),
          onGoAdmin: () => navigate(() => context.goNamed(RouteNames.admin)),
        );

    Widget wrapBody(Widget body) => FocusTraversalGroup(
          child: Focus(focusNode: _mainContentFocus, child: body),
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
                : Drawer(child: SafeArea(child: buildNav(showHeader: true))),
            body: Column(
              children: [
                const MaintenanceBanner(),
                Expanded(
                  child: isWide
                      ? Row(
                          children: [
                            if (_sidebarExpanded) ...[
                              SizedBox(
                                width: _kSidebarWidth,
                                child: buildNav(showHeader: false),
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
          SkipToContentLink(targetFocusNode: _mainContentFocus),
        ],
      ),
    );
  }
}

/// Navegación lateral. Se usa en el `Drawer` (móvil) y en el sidebar fijo
/// (ancho). [showHeader] muestra el nombre comercial arriba (solo drawer).
class _SidebarNav extends StatelessWidget {
  const _SidebarNav({
    required this.location,
    required this.section,
    required this.isAdmin,
    required this.commercialName,
    required this.showHeader,
    required this.onGoHome,
    required this.onGoMyMaterial,
    required this.onGoSettings,
    required this.onGoAdmin,
  });

  final String location;
  final String section;
  final bool isAdmin;
  final String commercialName;
  final bool showHeader;
  final VoidCallback onGoHome;
  final VoidCallback onGoMyMaterial;
  final ValueChanged<String> onGoSettings;
  final VoidCallback onGoAdmin;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final inSettings = location.startsWith(RoutePaths.accountSettings);
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
        // ─── Panel ───
        _NavTile(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: l.navDashboard,
          selected: location == RoutePaths.home,
          onTap: onGoHome,
        ),
        // ─── Mi Material ───
        _NavTile(
          icon: Icons.folder_copy_outlined,
          selectedIcon: Icons.folder_copy,
          label: l.navMyMaterial,
          selected: location == RoutePaths.myMaterial,
          onTap: onGoMyMaterial,
        ),
        // ─── Ajustes (submenú) ───
        _ExpandableNav(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          label: l.navSettings,
          active: inSettings,
          children: [
            _SubNavTile(
              label: l.settingsTabAccount,
              selected: inSettings && section == 'account',
              onTap: () => onGoSettings('account'),
            ),
            _SubNavTile(
              label: l.settingsTabWorkspace,
              selected: inSettings && section == 'workspace',
              onTap: () => onGoSettings('workspace'),
            ),
            _SubNavTile(
              label: l.settingsTabBilling,
              selected: inSettings && section == 'billing',
              onTap: () => onGoSettings('billing'),
            ),
            _SubNavTile(
              label: l.settingsTabSecurity,
              selected: inSettings && section == 'security',
              onTap: () => onGoSettings('security'),
            ),
          ],
        ),
        // ─── Administración (solo admin) ───
        if (isAdmin)
          _NavTile(
            icon: Icons.admin_panel_settings_outlined,
            selectedIcon: Icons.admin_panel_settings,
            label: l.navAdmin,
            selected: location.startsWith(RoutePaths.admin),
            onTap: onGoAdmin,
          ),
      ],
    );
  }
}

/// Item de primer nivel del sidebar (icono + label).
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(selected ? selectedIcon : icon, size: 20),
        title: Text(
          label,
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        selected: selected,
        selectedTileColor: scheme.primary.withValues(alpha: 0.10),
        selectedColor: scheme.primary,
        onTap: onTap,
      ),
    );
  }
}

/// Item de primer nivel desplegable (con subitems).
class _ExpandableNav extends StatelessWidget {
  const _ExpandableNav({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.active,
    required this.children,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool active;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Theme(
        // Quita las líneas divisorias por defecto del ExpansionTile.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          initiallyExpanded: active,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.only(left: 12),
          leading: Icon(active ? selectedIcon : icon, size: 20),
          title: Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? scheme.primary : null,
            ),
          ),
          children: children,
        ),
      ),
    );
  }
}

/// Subitem del submenú (sangrado, sin icono).
class _SubNavTile extends StatelessWidget {
  const _SubNavTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        label,
        style: context.textTheme.bodyMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.10),
      selectedColor: scheme.primary,
      onTap: onTap,
    );
  }
}
