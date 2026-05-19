import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/domain/entities/user_role.dart';
import 'package:myapp/features/auth/application/mfa_providers.dart';
import 'package:myapp/features/home/presentation/widgets/security_score_card.dart';

/// Dashboard de la zona privada (destino `/home` del shell).
///
/// **Rediseno Premium UI Fase 6**: pasamos de un layout simple con
/// StatCards + SecurityScoreCard a un dashboard estilo Stripe / Linear
/// con jerarquia clara:
///
/// 1. `PageHeader` con saludo personalizado + email.
/// 2. KPI Grid (4 `KpiCard`s): Role, MFA, Email verified, Member since.
///    Responsive: 1 col mobile / 2 tablet / 4 desktop.
/// 3. Seccion Quick Actions con 4 `PremiumCard`s clickables hacia las
///    paginas operativas (Files, Tokens, Webhooks, Activity).
/// 4. `SecurityScoreCard` (existente, donut chart + checklist).
/// 5. Banner CTA condicional si MFA off.
///
/// **Logica preservada al 100%**: providers, MFA detection, derivacion
/// del nombre, member since, etc. Solo cambia la presentacion.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final user = ref.watch(currentUserProvider);
    final role = ref.watch(currentRoleProvider);
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final mfaEnabled = ref.watch(mfaFactorsProvider).valueOrNull?.any(
              (f) => f.isVerified && f.type == 'totp',
            ) ??
        false;

    final displayName = (user?.userMetadata?['display_name'] as String?) ??
        (user?.userMetadata?['username'] as String?) ??
        user?.email?.split('@').first ??
        'user';
    final emailVerified = user?.emailConfirmedAt != null;
    final hasAvatar = (profile?.avatarUrl ?? '').isNotEmpty;
    final hasName = (profile?.displayName ?? '').trim().isNotEmpty;

    final memberSince = _formatMemberSince(context, user?.createdAt);
    final roleLabel = role == UserRole.admin ? l.roleAdmin : l.roleUser;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Header ───
              PageHeader(
                title: l.homeWelcomeUser(displayName),
                subtitle: user?.email != null
                    ? l.homeSignedInAs(user!.email!)
                    : null,
              ),
              AppSpacing.gapMd,
              // ─── KPI grid: 4 cards responsive ───
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    // Decision de columnas segun ancho:
                    // < 600 -> 1 col, < 900 -> 2 cols, < 1200 -> 4 cols,
                    // pero centrado, no estirado.
                    final int cols = w >= 900 ? 4 : (w >= 600 ? 2 : 1);
                    const double gap = AppSpacing.md;
                    final cardWidth =
                        (w - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: KpiCard(
                            icon: Icons.badge_outlined,
                            iconColor: role == UserRole.admin
                                ? context.colors.tertiary
                                : context.colors.primary,
                            value: roleLabel,
                            label: l.dashboardStatRole,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: KpiCard(
                            icon: Icons.shield_outlined,
                            iconColor: mfaEnabled
                                ? const Color(0xFF10B981)
                                : context.colors.error,
                            value: mfaEnabled
                                ? l.dashboardMfaOn
                                : l.dashboardMfaOff,
                            label: l.dashboardStatMfa,
                            onTap: () =>
                                context.goNamed(RouteNames.mfaSetup),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: KpiCard(
                            icon: Icons.mark_email_read_outlined,
                            iconColor: emailVerified
                                ? const Color(0xFF10B981)
                                : context.colors.error,
                            value: emailVerified
                                ? l.dashboardEmailVerified
                                : l.dashboardEmailPending,
                            label: l.dashboardStatEmail,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: KpiCard(
                            icon: Icons.calendar_today_outlined,
                            value: memberSince,
                            label: l.dashboardStatMemberSince,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              AppSpacing.gapXl,
              // ─── Quick actions ───
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: SectionHeader(
                  title: l.homeQuickActionsTitle,
                  subtitle: l.homeQuickActionsSubtitle,
                  compact: true,
                ),
              ),
              AppSpacing.gapMd,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final int cols = w >= 900 ? 4 : (w >= 600 ? 2 : 1);
                    const double gap = AppSpacing.md;
                    final cardWidth =
                        (w - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _QuickActionCard(
                            icon: Icons.cloud_outlined,
                            title: l.filesTitle,
                            subtitle: l.filesHint,
                            onTap: () => context.goNamed(RouteNames.files),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _QuickActionCard(
                            icon: Icons.vpn_key_outlined,
                            title: l.tokensTitle,
                            subtitle: l.tokensHint,
                            onTap: () => context.goNamed(RouteNames.tokens),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _QuickActionCard(
                            icon: Icons.webhook_outlined,
                            title: l.webhooksTitle,
                            subtitle: l.webhooksHint,
                            onTap: () => context.goNamed(RouteNames.webhooks),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _QuickActionCard(
                            icon: Icons.timeline,
                            title: l.activityTitle,
                            subtitle: l.activityHint,
                            onTap: () => context.goNamed(RouteNames.activity),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              AppSpacing.gapXl,
              // ─── Security ───
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: SecurityScoreCard(
                  title: l.dashboardSecurityTitle,
                  items: [
                    SecurityChecklistItem(
                      label: l.dashboardCheckEmail,
                      done: emailVerified,
                    ),
                    SecurityChecklistItem(
                      label: l.dashboardCheckMfa,
                      done: mfaEnabled,
                    ),
                    SecurityChecklistItem(
                      label: l.dashboardCheckAvatar,
                      done: hasAvatar,
                    ),
                    SecurityChecklistItem(
                      label: l.dashboardCheckName,
                      done: hasName,
                    ),
                  ],
                ),
              ),
              // ─── Banner MFA CTA (solo si off) ───
              if (!mfaEnabled) ...[
                AppSpacing.gapLg,
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: PremiumCard(
                    elevated: true,
                    onTap: () => context.goNamed(RouteNames.mfaSetup),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: context.colors.primary
                                .withValues(alpha: 0.12),
                            borderRadius: AppRadii.brMd,
                          ),
                          child: Icon(
                            Icons.shield_outlined,
                            color: context.colors.primary,
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
                                l.actionEnableMfa,
                                style: context.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l.settingsSecurityHint,
                                style:
                                    context.textTheme.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.chevron_right,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              AppSpacing.gapLg,
            ],
          ),
        ),
      ),
    );
  }

  String _formatMemberSince(BuildContext context, String? createdAt) {
    if (createdAt == null) return '—';
    final date = DateTime.tryParse(createdAt);
    if (date == null) return '—';
    final localeCode = Localizations.localeOf(context).languageCode;
    return DateFormat.yMMMd(localeCode).format(date.toLocal());
  }
}

/// Card de Quick Action: icon en avatar coloreado + titulo + subtitulo +
/// chevron. Inspirado en MaterialPro Apps grid pero adaptado a estilo
/// Stripe / Linear.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return PremiumCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: AppRadii.brMd,
            ),
            child: Icon(icon, color: scheme.primary, size: 20),
          ),
          AppSpacing.gapMd,
          Text(
            title,
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
