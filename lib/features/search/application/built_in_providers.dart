import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../domain/search_provider.dart';
import '../domain/search_result.dart';

/// Provider de "páginas" — navegación rápida a cualquier ruta de la app.
/// Pages siempre están disponibles, incluso con query vacía (sirven como
/// defaults). Las páginas solo-admin solo aparecen si el caller es admin.
class PagesSearchProvider extends SearchProvider {
  const PagesSearchProvider();

  @override
  String get name => 'pages';

  @override
  List<SearchResult> search(WidgetRef ref, AppLocalizations l, String query) {
    final isAdmin = ref.read(isAdminProvider);
    final section = l.searchSectionPages;

    final all = <SearchResult>[
      _page(
        id: 'page.home',
        title: l.navDashboard,
        section: section,
        icon: Icons.dashboard_outlined,
        route: RouteNames.home,
        keywords: const ['home', 'dashboard', 'inicio'],
      ),
      _page(
        id: 'page.settings',
        title: l.navSettings,
        section: section,
        icon: Icons.settings_outlined,
        route: RouteNames.accountSettings,
        keywords: const ['settings', 'preferences', 'ajustes', 'cuenta'],
      ),
      _page(
        id: 'page.notifications',
        title: l.notificationsTitle,
        section: section,
        icon: Icons.notifications_outlined,
        route: RouteNames.notifications,
        keywords: const ['notifications', 'alerts'],
      ),
      _page(
        id: 'page.plans',
        title: l.plansTitle,
        section: section,
        icon: Icons.sell_outlined,
        route: RouteNames.plans,
        keywords: const ['plans', 'pricing', 'subscription', 'billing'],
      ),
      _page(
        id: 'page.invoices',
        title: l.invoicesTitle,
        section: section,
        icon: Icons.receipt_long_outlined,
        route: RouteNames.invoices,
        keywords: const ['invoices', 'receipts', 'facturas'],
      ),
      _page(
        id: 'page.team',
        title: l.settingsTeam,
        section: section,
        icon: Icons.groups_outlined,
        route: RouteNames.team,
        keywords: const ['team', 'members', 'equipo'],
      ),
      _page(
        id: 'page.passkeys',
        title: l.settingsPasskeys,
        section: section,
        icon: Icons.fingerprint,
        route: RouteNames.passkeys,
        keywords: const ['passkeys', 'security'],
      ),
      _page(
        id: 'page.sessions',
        title: l.settingsSessions,
        section: section,
        icon: Icons.devices_outlined,
        route: RouteNames.sessions,
        keywords: const ['sessions', 'devices', 'sesiones'],
      ),
      if (isAdmin) ...[
        _page(
          id: 'page.admin',
          title: l.navAdmin,
          section: section,
          icon: Icons.admin_panel_settings_outlined,
          route: RouteNames.admin,
          keywords: const ['admin'],
        ),
        _page(
          id: 'page.admin.plans',
          title: l.adminPlansTitle,
          section: section,
          icon: Icons.sell_outlined,
          route: RouteNames.adminPlans,
          keywords: const ['admin', 'plans', 'pricing'],
        ),
        _page(
          id: 'page.admin.coupons',
          title: l.adminCouponsTitle,
          section: section,
          icon: Icons.local_offer_outlined,
          route: RouteNames.adminCoupons,
          keywords: const ['admin', 'coupons', 'promo'],
        ),
        _page(
          id: 'page.admin.branding',
          title: l.adminBrandingTitle,
          section: section,
          icon: Icons.palette_outlined,
          route: RouteNames.adminBranding,
          keywords: const ['admin', 'branding', 'stripe'],
        ),
        _page(
          id: 'page.admin.flags',
          title: l.adminFlagsTitle,
          section: section,
          icon: Icons.toggle_on_outlined,
          route: RouteNames.adminFlags,
          keywords: const ['admin', 'flags', 'features'],
        ),
        _page(
          id: 'page.admin.trash',
          title: l.adminTrashTitle,
          section: section,
          icon: Icons.delete_outline,
          route: RouteNames.adminTrash,
          keywords: const ['admin', 'trash', 'papelera', 'restore'],
        ),
      ],
    ];

    return all.where((r) => matchesQuery(r, query)).toList(growable: false);
  }

  SearchResult _page({
    required String id,
    required String title,
    required String section,
    required IconData icon,
    required String route,
    List<String> keywords = const [],
  }) {
    return SearchResult(
      id: id,
      title: title,
      section: section,
      icon: icon,
      keywords: keywords,
      onSelect: (ctx) {
        // Cerrar el palette antes de navegar para que el back stack
        // sea limpio.
        Navigator.of(ctx).maybePop();
        ctx.goNamed(route);
      },
    );
  }
}

/// Provider de "acciones" — cosas que el user puede DISPARAR sin
/// navegar: cambiar tema, abrir Stripe Dashboard externo, logout, etc.
class ActionsSearchProvider extends SearchProvider {
  const ActionsSearchProvider();

  @override
  String get name => 'actions';

  @override
  List<SearchResult> search(WidgetRef ref, AppLocalizations l, String query) {
    final section = l.searchSectionActions;

    final results = <SearchResult>[
      SearchResult(
        id: 'action.theme.system',
        title: l.searchActionThemeSystem,
        section: section,
        icon: Icons.brightness_auto_outlined,
        keywords: const ['theme', 'auto', 'sistema'],
        onSelect: (ctx) {
          Navigator.of(ctx).maybePop();
          ProviderScope.containerOf(ctx, listen: false)
              .read(themeNotifierProvider.notifier)
              .setMode(ThemeMode.system);
        },
      ),
      SearchResult(
        id: 'action.theme.light',
        title: l.searchActionThemeLight,
        section: section,
        icon: Icons.light_mode_outlined,
        keywords: const ['theme', 'light', 'claro'],
        onSelect: (ctx) {
          Navigator.of(ctx).maybePop();
          ProviderScope.containerOf(ctx, listen: false)
              .read(themeNotifierProvider.notifier)
              .setMode(ThemeMode.light);
        },
      ),
      SearchResult(
        id: 'action.theme.dark',
        title: l.searchActionThemeDark,
        section: section,
        icon: Icons.dark_mode_outlined,
        keywords: const ['theme', 'dark', 'oscuro'],
        onSelect: (ctx) {
          Navigator.of(ctx).maybePop();
          ProviderScope.containerOf(ctx, listen: false)
              .read(themeNotifierProvider.notifier)
              .setMode(ThemeMode.dark);
        },
      ),
      SearchResult(
        id: 'action.signout',
        title: l.actionSignOut,
        section: section,
        icon: Icons.logout,
        keywords: const ['signout', 'logout', 'salir', 'cerrar sesion'],
        priority: 30, // Acción peligrosa: aparece más abajo.
        onSelect: (ctx) {
          unawaited(Navigator.of(ctx).maybePop());
          unawaited(
            ProviderScope.containerOf(ctx, listen: false)
                .read(authRepositoryProvider)
                .signOut(),
          );
          // El listener del router redirige a /login automáticamente al
          // detectar la nueva sesión null.
        },
      ),
    ];

    return results.where((r) => matchesQuery(r, query)).toList(growable: false);
  }
}
