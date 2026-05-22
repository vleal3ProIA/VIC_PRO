import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/features/account/application/data_export_notifier.dart';
import 'package:myapp/features/account/application/profile_settings_notifier.dart';
import 'package:myapp/features/account/presentation/widgets/profile_failure_message.dart';
import 'package:myapp/features/account/presentation/widgets/settings_master_detail.dart';
import 'package:myapp/features/account/presentation/widgets/user_avatar.dart';
import 'package:myapp/features/auth/presentation/widgets/change_email_form.dart';
import 'package:myapp/features/auth/presentation/widgets/change_password_form.dart';
import 'package:myapp/features/auth/presentation/widgets/delete_account_form.dart';
import 'package:myapp/features/flags/application/feature_flags_providers.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

/// `/account-settings` -- pagina de configuracion del user.
///
/// **Rediseno (Fase 5 Premium UI)**: pasamos de una lista vertical de
/// 17 ListTiles a 4 tabs internas (Account / Workspace / Billing /
/// Security). Inspirado en MaterialPro y Stripe Account Settings.
///
/// **Logica preservada al 100%**:
/// - `ProfileSettingsNotifier`: state management de profile + saves.
/// - `DataExportNotifier`: export GDPR.
/// - Avatar upload con ImagePicker + content-type detection.
/// - Snackbars de feedback (saved / failure).
/// - Feature flag `audit_log_visible` para Activity + Audit log.
///
/// **Tabs**:
/// - Account: profile (avatar, name, username, email) + preferences
///   (language, theme).
/// - Workspace: files, tokens, webhooks, team, activity, audit log.
/// - Billing: plans, billing info, invoices, data export.
/// - Security: password, email, MFA, passkeys, sessions, delete.
class AccountSettingsPage extends ConsumerStatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  ConsumerState<AccountSettingsPage> createState() =>
      _AccountSettingsPageState();
}

class _AccountSettingsPageState extends ConsumerState<AccountSettingsPage> {
  final _displayNameCtrl = TextEditingController();
  String? _lastSyncedName;
  int _currentTab = 0;

  /// Última sección aplicada desde el query param `?section=`. El submenú
  /// "Ajustes" del sidebar navega con `?section=account|workspace|billing|
  /// security`; aquí lo mapeamos a la tab interna. Se guarda para no pisar
  /// los cambios de tab manuales del usuario en cada rebuild.
  String? _appliedSection;

  static const Map<String, int> _sectionToTab = {
    'account': 0,
    'workspace': 1,
    'billing': 2,
    'security': 3,
  };

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    super.dispose();
  }

  /// Abre el selector de imagenes y sube la elegida como avatar.
  Future<void> _pickAvatar(ProfileSettingsNotifier notifier) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final contentType = file.mimeType ?? _guessContentType(file.name);
    await notifier.uploadAvatar(bytes, contentType);
  }

  String _guessContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(profileSettingsNotifierProvider);
    final notifier = ref.read(profileSettingsNotifierProvider.notifier);
    final email = ref.watch(currentUserProvider)?.email ?? '';

    // El submenú "Ajustes" del sidebar navega con `?section=`. Lo aplicamos
    // a la tab activa solo cuando cambia (para no anular la navegación por
    // tabs en móvil).
    final section = GoRouterState.of(context).uri.queryParameters['section'];
    if (section != null &&
        section != _appliedSection &&
        _sectionToTab.containsKey(section)) {
      _appliedSection = section;
      _currentTab = _sectionToTab[section]!;
    }

    // Sincroniza el controller con el profile cuando carga / cambia.
    // Usamos `effectiveName` (no `displayName`) para que el campo editable
    // muestre SIEMPRE el nombre visible: editar y ver son el mismo valor.
    final profile = state.profile;
    if (profile != null && _lastSyncedName != profile.effectiveName) {
      _lastSyncedName = profile.effectiveName;
      _displayNameCtrl.text = profile.effectiveName;
    }

    // Snackbar al guardar con éxito.
    ref.listen<ProfileSettingsState>(profileSettingsNotifierProvider,
        (prev, next) {
      if (prev != null && next.savedTick > prev.savedTick) {
        context.showSnack(l.settingsSaved);
      }
      if (next.failure != null && next.failure != prev?.failure) {
        context.showSnack(
          profileFailureMessage(context, next.failure!),
          isError: true,
        );
      }
    });

    // Feedback al exportar los datos.
    ref.listen<DataExportState>(dataExportNotifierProvider, (prev, next) {
      if (prev?.status != DataExportStatus.success &&
          next.status == DataExportStatus.success) {
        context.showSnack(l.dataExportStarted);
      }
      if (prev?.status != DataExportStatus.failure &&
          next.status == DataExportStatus.failure) {
        context.showSnack(l.dataExportFailed, isError: true);
      }
    });

    return switch (state.status) {
      ProfileSettingsStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
      ProfileSettingsStatus.failure when state.profile == null => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: context.colors.error,
              ),
              const SizedBox(height: 12),
              Text(l.settingsLoadError),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: notifier.retry,
                child: Text(l.actionRetry),
              ),
            ],
          ),
        ),
      _ => _content(context, state, notifier, email, l),
    };
  }

  Widget _content(
    BuildContext context,
    ProfileSettingsState state,
    ProfileSettingsNotifier notifier,
    String email,
    AppLocalizations l,
  ) {
    return Center(
      child: ConstrainedBox(
        // Web: aprovechamos el ancho disponible (antes 880, ahora 1200) para
        // que el master-detail de las secciones tenga sitio de sobra.
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Header de pagina ───
            PageHeader(
              title: l.settingsTitle,
              subtitle: l.settingsSubtitle,
            ),
            // ─── Tabs (solo en móvil; en pantallas anchas la sección la
            // controla el submenú "Ajustes" del sidebar) ───
            if (context.isMobile)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                child: PremiumTabs(
                tabs: [
                  PremiumTabItem(
                    label: l.settingsTabAccount,
                    icon: Icons.person_outline,
                  ),
                  PremiumTabItem(
                    label: l.settingsTabWorkspace,
                    icon: Icons.workspaces_outline,
                  ),
                  PremiumTabItem(
                    label: l.settingsTabBilling,
                    icon: Icons.receipt_long_outlined,
                  ),
                  PremiumTabItem(
                    label: l.settingsTabSecurity,
                    icon: Icons.lock_outline,
                  ),
                ],
                currentIndex: _currentTab,
                onChanged: (i) => setState(() => _currentTab = i),
              ),
            ),
            // ─── Contenido de la tab activa ───
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                child: switch (_currentTab) {
                  0 => _AccountTab(
                      state: state,
                      notifier: notifier,
                      displayNameCtrl: _displayNameCtrl,
                      email: email,
                      onPickAvatar: () => _pickAvatar(notifier),
                    ),
                  1 => const _WorkspaceTab(),
                  2 => const _BillingTab(),
                  // Seguridad: en ancho usamos master-detail (menú + contenido
                  // limpio); en móvil mantenemos la lista de enlaces.
                  _ => context.isMobile
                      ? const _SecurityTab()
                      : const _SecurityMasterDetail(),
                },
              ),
            ),
            if (state.isSaving)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Tab 1: Account
// Profile (avatar + name + username + email) + preferences (language +
// theme). Datos editables del user.
// ═══════════════════════════════════════════════════════════════════

class _AccountTab extends ConsumerWidget {
  const _AccountTab({
    required this.state,
    required this.notifier,
    required this.displayNameCtrl,
    required this.email,
    required this.onPickAvatar,
  });

  final ProfileSettingsState state;
  final ProfileSettingsNotifier notifier;
  final TextEditingController displayNameCtrl;
  final String email;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final profile = state.profile!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── Card: Profile ───
        SectionHeader(title: l.settingsProfileSection, compact: true),
        AppSpacing.gapMd,
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Stack(
                  children: [
                    UserAvatar(
                      name: profile.effectiveName,
                      avatarUrl: profile.avatarUrl,
                      radius: 44,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: context.colors.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: state.isSaving ? null : onPickAvatar,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.camera_alt_outlined,
                              size: 16,
                              color: context.colors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: state.isSaving ? null : onPickAvatar,
                  child: Text(l.settingsChangeAvatar),
                ),
              ),
              const Divider(height: 24),
              TextField(
                controller: displayNameCtrl,
                enabled: !state.isSaving,
                decoration: InputDecoration(
                  labelText: l.settingsFieldDisplayName,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                onSubmitted: notifier.saveDisplayName,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: state.isSaving
                      ? null
                      : () => notifier.saveDisplayName(displayNameCtrl.text),
                  child: Text(l.actionSave),
                ),
              ),
              const Divider(height: 24),
              _ReadOnlyRow(
                icon: Icons.alternate_email,
                label: l.settingsFieldUsername,
                value: profile.username ?? '—',
              ),
              const SizedBox(height: 12),
              _ReadOnlyRow(
                icon: Icons.email_outlined,
                label: l.settingsFieldEmail,
                value: email,
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,
        // ─── Card: Preferences ───
        SectionHeader(title: l.settingsPreferencesSection, compact: true),
        AppSpacing.gapMd,
        PremiumCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.language_outlined),
                title: Text(l.settingsLanguage),
                trailing: DropdownButton<String>(
                  value: profile.locale,
                  underline: const SizedBox.shrink(),
                  onChanged: state.isSaving
                      ? null
                      : (code) {
                          if (code != null) {
                            notifier.changeLocale(Locale(code));
                          }
                        },
                  items: [
                    for (final loc in AppLocales.all)
                      DropdownMenuItem(
                        value: loc.languageCode,
                        child: Text(
                          '${AppLocales.flag[loc.languageCode] ?? ''}  '
                          '${AppLocales.nativeName[loc.languageCode] ?? loc.languageCode}',
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: Text(l.settingsTheme),
                trailing: DropdownButton<ThemeMode>(
                  value: profile.themeModeEnum,
                  underline: const SizedBox.shrink(),
                  onChanged: state.isSaving
                      ? null
                      : (mode) {
                          if (mode != null) {
                            notifier.changeThemeMode(mode);
                          }
                        },
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(context.l10n.themeSystem),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(context.l10n.themeLight),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(context.l10n.themeDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Tab 2: Workspace
// Files, tokens, webhooks, team, activity, audit log.
// ═══════════════════════════════════════════════════════════════════

class _WorkspaceTab extends ConsumerWidget {
  const _WorkspaceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final auditLogVisible = ref.watch(flagEnabledProvider('audit_log_visible'));

    return PremiumCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _LinkTile(
            icon: Icons.cloud_outlined,
            title: l.filesTitle,
            subtitle: l.filesHint,
            onTap: () => context.pushNamed(RouteNames.files),
          ),
          const Divider(height: 1),
          _LinkTile(
            icon: Icons.vpn_key_outlined,
            title: l.tokensTitle,
            subtitle: l.tokensHint,
            onTap: () => context.pushNamed(RouteNames.tokens),
          ),
          const Divider(height: 1),
          _LinkTile(
            icon: Icons.webhook_outlined,
            title: l.webhooksTitle,
            subtitle: l.webhooksHint,
            onTap: () => context.pushNamed(RouteNames.webhooks),
          ),
          const Divider(height: 1),
          _LinkTile(
            icon: Icons.groups_outlined,
            title: l.settingsTeam,
            subtitle: l.settingsTeamHint,
            onTap: () => context.pushNamed(RouteNames.team),
          ),
          // Activity y Audit log estan gated por feature flag
          // `audit_log_visible`.
          if (auditLogVisible) ...[
            const Divider(height: 1),
            _LinkTile(
              icon: Icons.timeline,
              title: l.activityTitle,
              subtitle: l.activityHint,
              onTap: () => context.pushNamed(RouteNames.activity),
            ),
            const Divider(height: 1),
            _LinkTile(
              icon: Icons.history,
              title: l.settingsAuditLog,
              subtitle: l.settingsAuditLogHint,
              onTap: () => context.pushNamed(RouteNames.auditLog),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Tab 3: Billing
// Plans, billing info, invoices, data export (GDPR).
// ═══════════════════════════════════════════════════════════════════

class _BillingTab extends ConsumerWidget {
  const _BillingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final exportState = ref.watch(dataExportNotifierProvider);

    return PremiumCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _LinkTile(
            icon: Icons.workspace_premium_outlined,
            title: l.settingsPlans,
            subtitle: l.settingsPlansHint,
            onTap: () => context.pushNamed(RouteNames.plans),
          ),
          const Divider(height: 1),
          _LinkTile(
            icon: Icons.receipt_long_outlined,
            title: l.settingsBillingInfo,
            subtitle: l.settingsBillingInfoHint,
            onTap: () => context.pushNamed(RouteNames.billingInfo),
          ),
          const Divider(height: 1),
          _LinkTile(
            icon: Icons.description_outlined,
            title: l.settingsInvoices,
            subtitle: l.settingsInvoicesHint,
            onTap: () => context.pushNamed(RouteNames.invoices),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l.settingsDownloadData),
            subtitle: Text(l.settingsDownloadDataHint),
            trailing: exportState.isBuilding
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.chevron_right),
            onTap: exportState.isBuilding
                ? null
                : () => ref
                    .read(dataExportNotifierProvider.notifier)
                    .exportAndDownload(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Tab 4: Security
// Password, email change, MFA, passkeys, sessions, delete account.
// El delete account va al final con estilo destructive.
// ═══════════════════════════════════════════════════════════════════

class _SecurityTab extends StatelessWidget {
  const _SecurityTab();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _LinkTile(
                icon: Icons.password_outlined,
                title: l.settingsChangePassword,
                onTap: () => context.pushNamed(RouteNames.changePassword),
              ),
              const Divider(height: 1),
              _LinkTile(
                icon: Icons.alternate_email,
                title: l.settingsChangeEmail,
                onTap: () => context.pushNamed(RouteNames.changeEmail),
              ),
              const Divider(height: 1),
              _LinkTile(
                icon: Icons.shield_outlined,
                title: context.l10n.actionEnableMfa,
                subtitle: l.settingsSecurityHint,
                onTap: () => context.pushNamed(RouteNames.mfaSetup),
              ),
              const Divider(height: 1),
              _LinkTile(
                icon: Icons.fingerprint,
                title: l.settingsPasskeys,
                subtitle: l.settingsPasskeysHint,
                onTap: () => context.pushNamed(RouteNames.passkeys),
              ),
              const Divider(height: 1),
              _LinkTile(
                icon: Icons.devices_outlined,
                title: l.settingsSessions,
                subtitle: l.settingsSessionsHint,
                onTap: () => context.pushNamed(RouteNames.sessions),
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,
        // ─── Danger zone ───
        SectionHeader(title: l.settingsDangerZone, compact: true),
        AppSpacing.gapMd,
        PremiumCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: context.colors.error,
            ),
            title: Text(
              l.settingsDeleteAccount,
              style: TextStyle(color: context.colors.error),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: context.colors.error,
            ),
            onTap: () => context.pushNamed(RouteNames.deleteAccount),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Tab 4 (ancho): Security master-detail
// Card menú izq + card contenido der. Los formularios (cambiar contraseña/
// email, eliminar cuenta) se embeben limpios reutilizando sus widgets de
// formulario. MFA/Passkeys/Sesiones abren a pantalla completa por ahora
// (se embeberán limpios en una sub-fase siguiente).
// ═══════════════════════════════════════════════════════════════════

class _SecurityMasterDetail extends StatelessWidget {
  const _SecurityMasterDetail();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SettingsMasterDetail(
      items: [
        SettingsDetailItem(
          icon: Icons.password_outlined,
          label: l.settingsChangePassword,
          builder: (_) => const ChangePasswordForm(),
        ),
        SettingsDetailItem(
          icon: Icons.alternate_email,
          label: l.settingsChangeEmail,
          builder: (_) => const ChangeEmailForm(),
        ),
        SettingsDetailItem(
          icon: Icons.shield_outlined,
          label: l.actionEnableMfa,
          builder: (_) => SettingsOpenFullScreen(
            icon: Icons.shield_outlined,
            title: l.actionEnableMfa,
            description: l.settingsSecurityHint,
            buttonLabel: l.filesOpen,
            routeName: RouteNames.mfaSetup,
          ),
        ),
        SettingsDetailItem(
          icon: Icons.fingerprint,
          label: l.settingsPasskeys,
          builder: (_) => SettingsOpenFullScreen(
            icon: Icons.fingerprint,
            title: l.settingsPasskeys,
            description: l.settingsPasskeysHint,
            buttonLabel: l.filesOpen,
            routeName: RouteNames.passkeys,
          ),
        ),
        SettingsDetailItem(
          icon: Icons.devices_outlined,
          label: l.settingsSessions,
          builder: (_) => SettingsOpenFullScreen(
            icon: Icons.devices_outlined,
            title: l.settingsSessions,
            description: l.settingsSessionsHint,
            buttonLabel: l.filesOpen,
            routeName: RouteNames.sessions,
          ),
        ),
        SettingsDetailItem(
          icon: Icons.delete_forever_outlined,
          label: l.settingsDeleteAccount,
          destructive: true,
          builder: (_) => const DeleteAccountForm(),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════

/// ListTile estandar para entradas de Settings que navegan a otra ruta.
/// Centraliza el patron (icon + title + optional subtitle + chevron).
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: context.colors.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              Text(value, style: context.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
