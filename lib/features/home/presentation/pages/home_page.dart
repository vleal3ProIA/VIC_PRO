import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/domain/entities/user_role.dart';
import 'package:myapp/features/auth/application/mfa_providers.dart';
import 'package:myapp/features/home/presentation/widgets/security_score_card.dart';
import 'package:myapp/features/home/presentation/widgets/stat_card.dart';

/// Dashboard de la zona privada (destino `/home` del shell). Tarjetas KPI con
/// el estado real de la cuenta + puntuación de seguridad.
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

    final displayName =
        (user?.userMetadata?['display_name'] as String?) ??
            (user?.userMetadata?['username'] as String?) ??
            user?.email?.split('@').first ??
            'user';
    final emailVerified = user?.emailConfirmedAt != null;
    final hasAvatar = (profile?.avatarUrl ?? '').isNotEmpty;
    final hasName = (profile?.displayName ?? '').trim().isNotEmpty;

    final memberSince = _formatMemberSince(context, user?.createdAt);
    final roleLabel = role == UserRole.admin ? l.roleAdmin : l.roleUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                l.homeWelcomeUser(displayName),
                style: context.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (user?.email != null) ...[
                const SizedBox(height: 4),
                Text(
                  l.homeSignedInAs(user!.email!),
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  StatCard(
                    icon: Icons.badge_outlined,
                    label: l.dashboardStatRole,
                    value: roleLabel,
                    accent: role == UserRole.admin
                        ? context.colors.tertiary
                        : context.colors.primary,
                  ),
                  StatCard(
                    icon: Icons.shield_outlined,
                    label: l.dashboardStatMfa,
                    value: mfaEnabled ? l.dashboardMfaOn : l.dashboardMfaOff,
                    accent: mfaEnabled
                        ? context.colors.tertiary
                        : context.colors.error,
                    onTap: () => context.goNamed(RouteNames.mfaSetup),
                  ),
                  StatCard(
                    icon: Icons.mark_email_read_outlined,
                    label: l.dashboardStatEmail,
                    value: emailVerified
                        ? l.dashboardEmailVerified
                        : l.dashboardEmailPending,
                    accent: emailVerified
                        ? context.colors.tertiary
                        : context.colors.error,
                  ),
                  StatCard(
                    icon: Icons.calendar_today_outlined,
                    label: l.dashboardStatMemberSince,
                    value: memberSince,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SecurityScoreCard(
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
              if (!mfaEnabled) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.shield_outlined,
                      color: context.colors.primary,
                    ),
                    title: Text(l.actionEnableMfa),
                    subtitle: Text(l.settingsSecurityHint),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.goNamed(RouteNames.mfaSetup),
                  ),
                ),
              ],
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
