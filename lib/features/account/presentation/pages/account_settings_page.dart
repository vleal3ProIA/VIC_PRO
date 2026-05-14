import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/account/application/profile_settings_notifier.dart';
import 'package:myapp/features/account/presentation/widgets/profile_failure_message.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

class AccountSettingsPage extends ConsumerStatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  ConsumerState<AccountSettingsPage> createState() =>
      _AccountSettingsPageState();
}

class _AccountSettingsPageState extends ConsumerState<AccountSettingsPage> {
  final _displayNameCtrl = TextEditingController();
  String? _lastSyncedName;

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(profileSettingsNotifierProvider);
    final notifier = ref.read(profileSettingsNotifierProvider.notifier);
    final email = ref.watch(currentUserProvider)?.email ?? '';

    // Sincroniza el controller con el profile cuando carga / cambia.
    final profile = state.profile;
    if (profile != null && _lastSyncedName != profile.displayName) {
      _lastSyncedName = profile.displayName;
      _displayNameCtrl.text = profile.displayName ?? '';
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.home),
        ),
        title: Text(l.settingsTitle),
      ),
      body: switch (state.status) {
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
      },
    );
  }

  Widget _content(
    BuildContext context,
    ProfileSettingsState state,
    ProfileSettingsNotifier notifier,
    String email,
    AppLocalizations l,
  ) {
    final profile = state.profile!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ----- Perfil -----
              _SectionHeader(l.settingsProfileSection),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _displayNameCtrl,
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
                              : () => notifier.saveDisplayName(
                                    _displayNameCtrl.text,
                                  ),
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
              ),
              const SizedBox(height: 24),

              // ----- Preferencias -----
              _SectionHeader(l.settingsPreferencesSection),
              Card(
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
              const SizedBox(height: 24),

              // ----- Seguridad -----
              _SectionHeader(l.settingsSecuritySection),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.password_outlined),
                      title: Text(l.settingsChangePassword),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.goNamed(RouteNames.changePassword),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.alternate_email),
                      title: Text(l.settingsChangeEmail),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.goNamed(RouteNames.changeEmail),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(context.l10n.actionEnableMfa),
                      subtitle: Text(l.settingsSecurityHint),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.goNamed(RouteNames.mfaSetup),
                    ),
                    const Divider(height: 1),
                    ListTile(
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
                      onTap: () =>
                          context.goNamed(RouteNames.deleteAccount),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (state.isSaving)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
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
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: context.textTheme.labelMedium?.copyWith(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
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
