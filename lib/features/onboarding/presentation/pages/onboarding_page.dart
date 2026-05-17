import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/features/account/application/profile_settings_notifier.dart';

import '../../application/onboarding_providers.dart';

/// `/onboarding` — wizard de bienvenida que se muestra UNA vez al user
/// tras su primer login exitoso. 3 pasos:
///
///   1. **Welcome** — saludo personalizado, explica para qué sirve la app
///      en una frase, botón "Empezar".
///   2. **Preferencias** — recordatorio visual del toggle de tema +
///      selector de idioma. Son ajustes que el user ya puede tocar
///      desde el AppBar/settings, pero aquí los hacemos prominentes.
///   3. **Equipo** — link rápido a /team para invitar (opcional, se
///      puede saltar).
///
/// Al terminar (o al saltar el wizard entero), llama
/// `mark_onboarding_completed` y navega a /home.
///
/// El router tiene un guard que redirige aquí mientras
/// `onboarding_completed_at` siga null. Así un user nuevo cae aquí
/// automáticamente tras el primer login y los antiguos no lo ven.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int _currentStep = 0;
  bool _saving = false;

  static const _totalSteps = 3;

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await ref.read(onboardingDataSourceProvider).markCompleted();
      ref.invalidate(onboardingCompletedProvider);
      if (!mounted) return;
      context.goNamed(RouteNames.home);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(context.l10n.onboardingFinishError, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final profile = ref.watch(profileSettingsNotifierProvider).profile;
    final displayName = profile?.displayName?.trim();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppMaxWidths.form),
            child: Column(
              children: [
                _Header(
                  currentStep: _currentStep,
                  totalSteps: _totalSteps,
                  onSkip: _saving ? null : _finish,
                ),
                AppSpacing.gapLg,
                Expanded(
                  child: SingleChildScrollView(
                    padding: AppSpacing.paddingLg,
                    child: switch (_currentStep) {
                      0 => _WelcomeStep(
                          displayName: displayName,
                          appTitle: l.appTitle,
                        ),
                      1 => const _PreferencesStep(),
                      _ => const _TeamStep(),
                    },
                  ),
                ),
                _NavBar(
                  currentStep: _currentStep,
                  totalSteps: _totalSteps,
                  saving: _saving,
                  onBack: _currentStep == 0
                      ? null
                      : () => setState(() => _currentStep--),
                  onNext: _saving
                      ? null
                      : () {
                          if (_currentStep < _totalSteps - 1) {
                            setState(() => _currentStep++);
                          } else {
                            _finish();
                          }
                        },
                ),
                AppSpacing.gapLg,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Header ─────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.currentStep,
    required this.totalSteps,
    required this.onSkip,
  });
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.onboardingStepCounter(currentStep + 1, totalSteps),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          if (onSkip != null)
            TextButton(
              onPressed: onSkip,
              child: Text(l.onboardingSkipAll),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── NavBar ─────────────────────────────

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.currentStep,
    required this.totalSteps,
    required this.saving,
    required this.onBack,
    required this.onNext,
  });
  final int currentStep;
  final int totalSteps;
  final bool saving;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isLast = currentStep == totalSteps - 1;
    return Padding(
      padding: AppSpacing.horizontalLg,
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(l.onboardingBack),
            onPressed: onBack,
          ),
          const Spacer(),
          FilledButton.icon(
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isLast ? Icons.check : Icons.arrow_forward, size: 18),
            label: Text(isLast ? l.onboardingFinish : l.onboardingNext),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Step 1: Welcome ─────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.displayName, required this.appTitle});
  final String? displayName;
  final String appTitle;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.waving_hand_outlined,
          size: 72,
          color: scheme.primary,
        ),
        AppSpacing.gapMd,
        Text(
          displayName == null || displayName!.isEmpty
              ? l.onboardingWelcomeTitleGeneric(appTitle)
              : l.onboardingWelcomeTitle(displayName!, appTitle),
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapSm,
        Text(
          l.onboardingWelcomeBody,
          style: context.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ───────────────────────── Step 2: Preferences ─────────────────────────

class _PreferencesStep extends ConsumerWidget {
  const _PreferencesStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final mode = ref.watch(themeNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.onboardingPreferencesTitle,
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        AppSpacing.gapSm,
        Text(
          l.onboardingPreferencesBody,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        AppSpacing.gapLg,
        Card(
          child: Padding(
            padding: AppSpacing.paddingMd,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: Text(l.settingsTheme),
                  subtitle: Text(
                    switch (mode) {
                      ThemeMode.system => l.themeSystem,
                      ThemeMode.light => l.themeLight,
                      ThemeMode.dark => l.themeDark,
                    },
                  ),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: const Icon(Icons.brightness_auto_outlined),
                        tooltip: l.themeSystem,
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: const Icon(Icons.light_mode_outlined),
                        tooltip: l.themeLight,
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: const Icon(Icons.dark_mode_outlined),
                        tooltip: l.themeDark,
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) {
                      ref
                          .read(themeNotifierProvider.notifier)
                          .setMode(s.first);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Step 3: Team ───────────────────────────

class _TeamStep extends StatelessWidget {
  const _TeamStep();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.onboardingTeamTitle,
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        AppSpacing.gapSm,
        Text(
          l.onboardingTeamBody,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        AppSpacing.gapLg,
        Card(
          color: context.colors.secondaryContainer,
          child: ListTile(
            leading: Icon(
              Icons.groups_outlined,
              color: context.colors.onSecondaryContainer,
            ),
            title: Text(l.onboardingTeamInviteCta),
            subtitle: Text(l.onboardingTeamInviteHint),
            trailing: FilledButton.tonal(
              onPressed: () => context.goNamed(RouteNames.team),
              child: Text(l.onboardingTeamGo),
            ),
          ),
        ),
        AppSpacing.gapMd,
        Text(
          l.onboardingTeamSkipNote,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
