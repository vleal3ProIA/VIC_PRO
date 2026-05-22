import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/presentation/widgets/settings_master_detail.dart'
    show SettingsOpenFullScreen;
import 'package:myapp/features/admin/presentation/pages/admin_trash_page.dart'
    show AdminTrashView;
import 'package:myapp/features/admin_acl/application/admin_acl_providers.dart';
import 'package:myapp/features/admin_acl/domain/admin_capability.dart';
import 'package:myapp/features/admin_acl/presentation/pages/admin_admins_page.dart'
    show AdminAdminsView;
import 'package:myapp/features/admin_metrics/presentation/pages/admin_metrics_page.dart'
    show AdminMetricsView;
import 'package:myapp/features/admin_users/presentation/pages/admin_users_page.dart'
    show AdminUsersView;
import 'package:myapp/features/audit_center/presentation/pages/admin_audit_page.dart'
    show AdminAuditView;
import 'package:myapp/features/billing/presentation/pages/admin_branding_page.dart'
    show AdminBrandingView;
import 'package:myapp/features/billing/presentation/pages/admin_coupons_page.dart'
    show AdminCouponsView;
import 'package:myapp/features/billing/presentation/pages/admin_plans_page.dart'
    show AdminPlansView;
import 'package:myapp/features/branding/presentation/pages/admin_app_branding_page.dart'
    show AdminAppBrandingView;
import 'package:myapp/features/broadcasts/presentation/pages/admin_broadcasts_page.dart'
    show AdminBroadcastsView;
import 'package:myapp/features/emails/presentation/pages/admin_email_log_page.dart'
    show AdminEmailLogView;
import 'package:myapp/features/flags/presentation/pages/admin_flags_page.dart'
    show AdminFlagsView;
import 'package:myapp/features/help/presentation/pages/admin_changelog_page.dart'
    show AdminChangelogView;
import 'package:myapp/features/status/presentation/pages/admin_incidents_page.dart'
    show AdminIncidentsView;
import 'package:myapp/generated/l10n/app_localizations.dart';

/// `/admin` — entry point del area administrativa.
///
/// **Rediseno Premium UI Fase 7**: pasamos de 13 ListTiles seguidos
/// (sin agrupacion ni jerarquia visual) a un dashboard con 5 secciones
/// tematicas y cards Premium con iconos coloreados estilo Linear/Notion.
///
/// **Secciones**:
/// 1. **Security & monitoring**: Audit Center, Incidents, Trash.
/// 2. **Access & users**: Users, Feature flags.
/// 3. **Billing & monetization**: Plans, Coupons, Stripe branding.
/// 4. **Communications**: Broadcasts, Email log, Changelog.
/// 5. **Content & analytics**: App branding, Metrics.
///
/// **Logica preservada al 100%**: los 13 destinos siguen accesibles
/// con sus mismas rutas y `RouteNames`. Solo cambia la presentacion.
/// El acceso esta protegido por partida doble (router guard + el
/// destino solo aparece para `admin` en el shell).
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final role = ref.watch(currentRoleProvider);

    // PR-Super-A2: leemos capabilities + flag super para filtrar las
    // cards. Mientras carga (set vacio + super=false), NO filtramos --
    // mostramos todo para evitar flash. Cuando resuelve, ocultamos las
    // cards que el user no pueda usar. Super ve TODO sin filtrar.
    final caps =
        ref.watch(myCapabilitiesProvider).valueOrNull ?? const <String>{};
    final isSuper = ref.watch(isSuperAdminProvider).valueOrNull ?? false;
    final stillLoading = ref.watch(myCapabilitiesProvider).valueOrNull == null;

    final destinations = _AdminDestinations(l);

    bool isAllowed(_AdminDestination d) {
      if (isSuper) return true;
      if (stillLoading) return true; // evita flash
      final cap = d.capability;
      if (cap == null) return true; // cards sin cap-gate
      return caps.contains(cap);
    }

    List<_AdminDestination> filter(List<_AdminDestination> list) =>
        list.where(isAllowed).toList(growable: false);

    final security = filter(destinations.security);
    final access = filter(destinations.access);
    final billing = filter(destinations.billing);
    final communications = filter(destinations.communications);
    final content = filter(destinations.content);
    final superSection =
        isSuper ? destinations.superTools : const <_AdminDestination>[];

    // Secciones no vacías, en orden. Usadas tanto por el dashboard (móvil)
    // como por el master-detail (ancho).
    final sections = <_AdminSection>[
      if (superSection.isNotEmpty)
        _AdminSection(
          l.adminSectionSuper,
          l.adminSectionSuperHint,
          superSection,
        ),
      if (security.isNotEmpty)
        _AdminSection(
          l.adminSectionSecurity,
          l.adminSectionSecurityHint,
          security,
        ),
      if (access.isNotEmpty)
        _AdminSection(
          l.adminSectionAccess,
          l.adminSectionAccessHint,
          access,
        ),
      if (billing.isNotEmpty)
        _AdminSection(
          l.adminSectionBilling,
          l.adminSectionBillingHint,
          billing,
        ),
      if (communications.isNotEmpty)
        _AdminSection(
          l.adminSectionCommunications,
          l.adminSectionCommunicationsHint,
          communications,
        ),
      if (content.isNotEmpty)
        _AdminSection(
          l.adminSectionContent,
          l.adminSectionContentHint,
          content,
        ),
    ];

    final showEmpty = !isSuper && !stillLoading && sections.isEmpty;

    final headerBadge = isSuper
        ? PremiumBadge(
            label: l.adminAdminsBadgeSuper,
            variant: PremiumBadgeVariant.warning,
            icon: Icons.workspace_premium_rounded,
          )
        : PremiumBadge(
            label: '${l.adminRoleBadge} · ${role.name}',
            variant: PremiumBadgeVariant.info,
            icon: Icons.verified_user_rounded,
          );

    // Móvil: dashboard de cards (como hasta ahora). Ancho: master-detail.
    return context.isMobile
        ? _AdminDashboard(
            sections: sections,
            headerBadge: headerBadge,
            showEmpty: showEmpty,
          )
        : _AdminMasterDetail(
            sections: sections,
            headerBadge: headerBadge,
            showEmpty: showEmpty,
          );
  }
}

/// Una sección del área de admin: título + subtítulo + sus destinos.
@immutable
class _AdminSection {
  const _AdminSection(this.title, this.subtitle, this.items);
  final String title;
  final String subtitle;
  final List<_AdminDestination> items;
}

/// Dashboard de cards agrupadas por sección (móvil + fallback). Es el layout
/// "histórico" de `/admin`.
class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({
    required this.sections,
    required this.headerBadge,
    required this.showEmpty,
  });

  final List<_AdminSection> sections;
  final Widget headerBadge;
  final bool showEmpty;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: l.adminTitle,
                subtitle: l.adminSubtitle,
                actions: [headerBadge],
              ),
              AppSpacing.gapLg,
              for (final s in sections) ...[
                _Section(title: s.title, subtitle: s.subtitle, items: s.items),
                AppSpacing.gapLg,
              ],
              if (showEmpty) const _NoCapabilitiesCard(),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Master-detail del área de admin (pantalla ancha): menú de secciones a la
/// izquierda + panel del destino seleccionado a la derecha. Los destinos ya
/// embebidos muestran su `*View(embedded: true)`; el resto abre a pantalla
/// completa (se irán embebiendo por lotes).
class _AdminMasterDetail extends StatefulWidget {
  const _AdminMasterDetail({
    required this.sections,
    required this.headerBadge,
    required this.showEmpty,
  });

  final List<_AdminSection> sections;
  final Widget headerBadge;
  final bool showEmpty;

  @override
  State<_AdminMasterDetail> createState() => _AdminMasterDetailState();
}

class _AdminMasterDetailState extends State<_AdminMasterDetail> {
  /// Ruta del destino seleccionado (key estable entre rebuilds).
  String? _selectedRoute;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final allItems = [for (final s in widget.sections) ...s.items];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: l.adminTitle,
                subtitle: l.adminSubtitle,
                actions: [widget.headerBadge],
              ),
              AppSpacing.gapLg,
              if (allItems.isEmpty)
                if (widget.showEmpty)
                  const _NoCapabilitiesCard()
                else
                  const SizedBox.shrink()
              else
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: _buildMasterDetail(context, l, allItems),
                ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMasterDetail(
    BuildContext context,
    AppLocalizations l,
    List<_AdminDestination> allItems,
  ) {
    final scheme = context.colors;
    final selected = allItems.firstWhere(
      (d) => d.route == _selectedRoute,
      orElse: () => allItems.first,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Menú de secciones ───
        SizedBox(
          width: 260,
          child: PremiumCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final section in widget.sections) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: Text(
                      section.title,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  for (final d in section.items)
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(d.icon, size: 20, color: d.colorSeed),
                      title: Text(
                        d.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: d.route == selected.route
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      selected: d.route == selected.route,
                      selectedTileColor: scheme.primary.withValues(alpha: 0.10),
                      selectedColor: scheme.primary,
                      onTap: () => setState(() => _selectedRoute = d.route),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        // ─── Panel del destino seleccionado ───
        Expanded(
          child: PremiumCard(
            child: KeyedSubtree(
              key: ValueKey(selected.route),
              child: selected.embeddedBuilder != null
                  ? selected.embeddedBuilder!(context)
                  : SettingsOpenFullScreen(
                      icon: selected.icon,
                      title: selected.title,
                      description: selected.hint,
                      buttonLabel: l.filesOpen,
                      routeName: selected.route,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Card de "no tienes capabilities" (admin sin permisos asignados).
class _NoCapabilitiesCard extends StatelessWidget {
  const _NoCapabilitiesCard();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: PremiumCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              color: scheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                l.adminNoCapabilities,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Definicion de los 13 destinos agrupados por seccion. Vive en una
/// clase para que el build() de AdminPage no se llene de constructores
/// y para que cada destino tenga (icon, color, title, hint, route)
/// junto -- mas facil de mantener si anyades / quitas uno.
class _AdminDestinations {
  _AdminDestinations(this.l);

  final AppLocalizations l;

  List<_AdminDestination> get security => [
        _AdminDestination(
          icon: Icons.shield_outlined,
          colorSeed: const Color(0xFFEF4444), // red-500
          title: l.adminAuditTitle,
          hint: l.adminAuditHint,
          route: RouteNames.adminAudit,
          capability: AdminCapability.runAudits,
          embeddedBuilder: (_) => const AdminAuditView(embedded: true),
        ),
        _AdminDestination(
          icon: Icons.health_and_safety_outlined,
          colorSeed: const Color(0xFFF59E0B), // amber-500
          title: l.adminIncidentsTitle,
          hint: l.adminIncidentsHint,
          route: RouteNames.adminIncidents,
          capability: AdminCapability.manageIncidents,
          embeddedBuilder: (_) => const AdminIncidentsView(embedded: true),
        ),
        _AdminDestination(
          icon: Icons.delete_outline_rounded,
          colorSeed: const Color(0xFF6B7280), // gray-500
          title: l.adminTrashTitle,
          hint: l.adminTrashHint,
          route: RouteNames.adminTrash,
          capability: AdminCapability.manageTrash,
          embeddedBuilder: (_) => const AdminTrashView(embedded: true),
        ),
      ];

  List<_AdminDestination> get access => [
        _AdminDestination(
          icon: Icons.people_alt_outlined,
          colorSeed: const Color(0xFF3B82F6), // blue-500
          title: l.adminUsersTitle,
          hint: l.adminUsersHint,
          route: RouteNames.adminUsers,
          capability: AdminCapability.manageUsers,
          embeddedBuilder: (_) => const AdminUsersView(embedded: true),
        ),
        _AdminDestination(
          icon: Icons.toggle_on_outlined,
          colorSeed: const Color(0xFF8B5CF6), // violet-500
          title: l.adminFlagsTitle,
          hint: l.adminFlagsHint,
          route: RouteNames.adminFlags,
          capability: AdminCapability.manageFlags,
          embeddedBuilder: (_) => const AdminFlagsView(embedded: true),
        ),
      ];

  List<_AdminDestination> get billing => [
        _AdminDestination(
          icon: Icons.sell_outlined,
          colorSeed: const Color(0xFF10B981), // emerald-500
          title: l.adminPlansTitle,
          hint: l.adminPlansHint,
          route: RouteNames.adminPlans,
          capability: AdminCapability.managePlans,
          embeddedBuilder: (_) => const AdminPlansView(embedded: true),
        ),
        _AdminDestination(
          icon: Icons.local_offer_outlined,
          colorSeed: const Color(0xFFEC4899), // pink-500
          title: l.adminCouponsTitle,
          hint: l.adminCouponsHint,
          route: RouteNames.adminCoupons,
          capability: AdminCapability.manageCoupons,
          embeddedBuilder: (_) => const AdminCouponsView(embedded: true),
        ),
        _AdminDestination(
          icon: Icons.palette_outlined,
          colorSeed: const Color(0xFF14B8A6), // teal-500
          title: l.adminBrandingTitle,
          hint: l.adminBrandingHint,
          route: RouteNames.adminBranding,
          capability: AdminCapability.manageBranding,
          embeddedBuilder: (_) => const AdminBrandingView(embedded: true),
        ),
      ];

  List<_AdminDestination> get communications => [
        _AdminDestination(
          icon: Icons.campaign_outlined,
          colorSeed: const Color(0xFF0EA5E9), // sky-500
          title: l.broadcastsTitle,
          hint: l.broadcastsHint,
          route: RouteNames.adminBroadcasts,
          capability: AdminCapability.manageBroadcasts,
          embeddedBuilder: (_) => const AdminBroadcastsView(embedded: true),
        ),
        _AdminDestination(
          icon: Icons.mark_email_read_outlined,
          colorSeed: const Color(0xFF6366F1), // indigo-500
          title: l.adminEmailLogTitle,
          hint: l.adminEmailLogHint,
          route: RouteNames.adminEmailLog,
          capability: AdminCapability.viewEmailLog,
          embeddedBuilder: (_) => const AdminEmailLogView(embedded: true),
        ),
        _AdminDestination(
          icon: Icons.article_outlined,
          colorSeed: const Color(0xFF9333EA), // purple-600
          title: l.adminChangelogTitle,
          hint: l.adminChangelogHint,
          route: RouteNames.adminChangelog,
          capability: AdminCapability.manageChangelog,
          embeddedBuilder: (_) => const AdminChangelogView(embedded: true),
        ),
      ];

  List<_AdminDestination> get content => [
        _AdminDestination(
          icon: Icons.brush_outlined,
          colorSeed: const Color(0xFFF97316), // orange-500
          title: l.adminAppBrandingTitle,
          hint: l.adminAppBrandingHint,
          route: RouteNames.adminAppBranding,
          capability: AdminCapability.manageAppBranding,
          embeddedBuilder: (_) => const AdminAppBrandingView(embedded: true),
        ),
        _AdminDestination(
          icon: Icons.insights_outlined,
          colorSeed: const Color(0xFF22C55E), // green-500
          title: l.adminMetricsTitle,
          hint: l.adminMetricsHint,
          route: RouteNames.adminMetrics,
          capability: AdminCapability.viewMetrics,
          embeddedBuilder: (_) => const AdminMetricsView(embedded: true),
        ),
      ];

  /// Tools exclusivos del super admin. NO tienen capability gate --
  /// se filtran por `isSuperAdmin` en el build de AdminPage. Hoy
  /// solo "Manage admins"; en el futuro pueden venir mas (system
  /// settings, etc).
  List<_AdminDestination> get superTools => [
        _AdminDestination(
          icon: Icons.admin_panel_settings_outlined,
          colorSeed: const Color(0xFFFBBF24), // amber-400
          title: l.adminAdminsTitle,
          hint: l.adminAdminsHint,
          route: RouteNames.adminAdmins,
          embeddedBuilder: (_) => const AdminAdminsView(embedded: true),
        ),
      ];
}

@immutable
class _AdminDestination {
  const _AdminDestination({
    required this.icon,
    required this.colorSeed,
    required this.title,
    required this.hint,
    required this.route,
    this.capability,
    this.embeddedBuilder,
  });

  final IconData icon;

  /// Color base del icono. Cada destino tiene su propio matiz para que
  /// la vista global sea "leible" -- el ojo identifica a primera vista
  /// "el amarillo es incidents", "el verde es plans", etc.
  final Color colorSeed;

  final String title;
  final String hint;
  final String route;

  /// Capability requerida para que la card se muestre. `null` =
  /// siempre visible para cualquier admin (ej. la card de super tools
  /// se filtra por `isSuperAdmin` aparte). El super admin ve TODAS
  /// las cards independientemente de este campo.
  final String? capability;

  /// Builder del contenido embebido en el panel del master-detail. Si es
  /// null, el panel muestra un botón que abre la ruta a pantalla completa.
  final WidgetBuilder? embeddedBuilder;
}

/// Una seccion: header + grid responsive de destinos.
///
/// Layout: usamos `Wrap` con `cardWidth` calculado dinamicamente segun
/// el ancho disponible. < 600 -> 1 col, < 900 -> 2 cols, >= 900 -> 3
/// cols. Asi siempre ocupamos el ancho completo sin huecos raros.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<_AdminDestination> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: title,
            subtitle: subtitle,
            compact: true,
          ),
          AppSpacing.gapMd,
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final int cols = w >= 900 ? 3 : (w >= 600 ? 2 : 1);
              const double gap = AppSpacing.md;
              final cardWidth = (w - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final d in items)
                    SizedBox(
                      width: cardWidth,
                      child: _DestinationCard(destination: d),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Una card de destino. PremiumCard clickable con:
/// - Tile cuadrado coloreado con el icono semantico arriba a la izq.
/// - Titulo bold.
/// - Hint en gris.
/// - Chevron sutil a la derecha que indica "navega aqui".
class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination});

  final _AdminDestination destination;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PremiumCard(
      onTap: () => context.pushNamed(destination.route),
      padding: const EdgeInsets.all(AppSpacing.md),
      semanticLabel: destination.title,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tile coloreado con el icono. Background con opacity baja
          // para que el color "respire" sin gritar.
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: destination.colorSeed.withValues(alpha: 0.12),
              borderRadius: AppRadii.brSm,
            ),
            child: Icon(
              destination.icon,
              color: destination.colorSeed,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  destination.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        height: 1.2,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  destination.hint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.arrow_forward_rounded,
            size: 16,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}
