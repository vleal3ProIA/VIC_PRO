import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
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

    final destinations = _AdminDestinations(l);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Header con rol como trailing ───
              PageHeader(
                title: l.adminTitle,
                subtitle: l.adminSubtitle,
                actions: [
                  PremiumBadge(
                    label: '${l.adminRoleBadge} · ${role.name}',
                    variant: PremiumBadgeVariant.info,
                    icon: Icons.verified_user_rounded,
                  ),
                ],
              ),
              AppSpacing.gapLg,
              _Section(
                title: l.adminSectionSecurity,
                subtitle: l.adminSectionSecurityHint,
                items: destinations.security,
              ),
              AppSpacing.gapLg,
              _Section(
                title: l.adminSectionAccess,
                subtitle: l.adminSectionAccessHint,
                items: destinations.access,
              ),
              AppSpacing.gapLg,
              _Section(
                title: l.adminSectionBilling,
                subtitle: l.adminSectionBillingHint,
                items: destinations.billing,
              ),
              AppSpacing.gapLg,
              _Section(
                title: l.adminSectionCommunications,
                subtitle: l.adminSectionCommunicationsHint,
                items: destinations.communications,
              ),
              AppSpacing.gapLg,
              _Section(
                title: l.adminSectionContent,
                subtitle: l.adminSectionContentHint,
                items: destinations.content,
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
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
        ),
        _AdminDestination(
          icon: Icons.health_and_safety_outlined,
          colorSeed: const Color(0xFFF59E0B), // amber-500
          title: l.adminIncidentsTitle,
          hint: l.adminIncidentsHint,
          route: RouteNames.adminIncidents,
        ),
        _AdminDestination(
          icon: Icons.delete_outline_rounded,
          colorSeed: const Color(0xFF6B7280), // gray-500
          title: l.adminTrashTitle,
          hint: l.adminTrashHint,
          route: RouteNames.adminTrash,
        ),
      ];

  List<_AdminDestination> get access => [
        _AdminDestination(
          icon: Icons.people_alt_outlined,
          colorSeed: const Color(0xFF3B82F6), // blue-500
          title: l.adminUsersTitle,
          hint: l.adminUsersHint,
          route: RouteNames.adminUsers,
        ),
        _AdminDestination(
          icon: Icons.toggle_on_outlined,
          colorSeed: const Color(0xFF8B5CF6), // violet-500
          title: l.adminFlagsTitle,
          hint: l.adminFlagsHint,
          route: RouteNames.adminFlags,
        ),
      ];

  List<_AdminDestination> get billing => [
        _AdminDestination(
          icon: Icons.sell_outlined,
          colorSeed: const Color(0xFF10B981), // emerald-500
          title: l.adminPlansTitle,
          hint: l.adminPlansHint,
          route: RouteNames.adminPlans,
        ),
        _AdminDestination(
          icon: Icons.local_offer_outlined,
          colorSeed: const Color(0xFFEC4899), // pink-500
          title: l.adminCouponsTitle,
          hint: l.adminCouponsHint,
          route: RouteNames.adminCoupons,
        ),
        _AdminDestination(
          icon: Icons.palette_outlined,
          colorSeed: const Color(0xFF14B8A6), // teal-500
          title: l.adminBrandingTitle,
          hint: l.adminBrandingHint,
          route: RouteNames.adminBranding,
        ),
      ];

  List<_AdminDestination> get communications => [
        _AdminDestination(
          icon: Icons.campaign_outlined,
          colorSeed: const Color(0xFF0EA5E9), // sky-500
          title: l.broadcastsTitle,
          hint: l.broadcastsHint,
          route: RouteNames.adminBroadcasts,
        ),
        _AdminDestination(
          icon: Icons.mark_email_read_outlined,
          colorSeed: const Color(0xFF6366F1), // indigo-500
          title: l.adminEmailLogTitle,
          hint: l.adminEmailLogHint,
          route: RouteNames.adminEmailLog,
        ),
        _AdminDestination(
          icon: Icons.article_outlined,
          colorSeed: const Color(0xFF9333EA), // purple-600
          title: l.adminChangelogTitle,
          hint: l.adminChangelogHint,
          route: RouteNames.adminChangelog,
        ),
      ];

  List<_AdminDestination> get content => [
        _AdminDestination(
          icon: Icons.brush_outlined,
          colorSeed: const Color(0xFFF97316), // orange-500
          title: l.adminAppBrandingTitle,
          hint: l.adminAppBrandingHint,
          route: RouteNames.adminAppBranding,
        ),
        _AdminDestination(
          icon: Icons.insights_outlined,
          colorSeed: const Color(0xFF22C55E), // green-500
          title: l.adminMetricsTitle,
          hint: l.adminMetricsHint,
          route: RouteNames.adminMetrics,
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
  });

  final IconData icon;

  /// Color base del icono. Cada destino tiene su propio matiz para que
  /// la vista global sea "leible" -- el ojo identifica a primera vista
  /// "el amarillo es incidents", "el verde es plans", etc.
  final Color colorSeed;

  final String title;
  final String hint;
  final String route;
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
      onTap: () => context.goNamed(destination.route),
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
