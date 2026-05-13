import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/core/widgets/pin_code_input.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/mfa_challenge_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';

/// Pantalla intermedia entre el login con password y el home, cuando el
/// usuario tiene MFA habilitado. Aquí mete el código de su app
/// autenticadora para subir AAL=1 → AAL=2.
class MfaChallengePage extends ConsumerWidget {
  const MfaChallengePage({super.key});

  static const double _reservedHeight = 580;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cuando el verify de MFA tiene éxito, AAL sube a aal2 y el guard del
    // router (que watchea authStateChangesProvider) redirige a /home.
    // Por consistencia con OTP/MagicLink, NO navegamos manualmente.

    final state = ref.watch(mfaChallengeNotifierProvider);
    final notifier = ref.read(mfaChallengeNotifierProvider.notifier);
    final l = context.l10n;

    final generalError = state.failure != null
        ? authFailureMessage(context, state.failure!)
        : null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.l10n.appTitle,
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // Logout para que el usuario pueda salir si no puede completar
          // el MFA (p. ej. perdió el dispositivo).
          IconButton(
            tooltip: l.actionSignOut,
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) {
                context.goNamed(RouteNames.welcome);
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          leading: Icon(
            Icons.shield_outlined,
            size: 56,
            color: context.colors.primary,
          ),
          title: l.mfaChallengeTitle,
          subtitle: l.mfaChallengeSubtitle,
          child: switch (state.status) {
            MfaChallengeStatus.loading => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            _ => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  PinCodeInput(
                    onChanged: notifier.codeChanged,
                    onCompleted: (_) => notifier.verify(),
                    enabled: !state.isVerifying && state.factor != null,
                    hasError: state.failure != null,
                  ),
                  GeneralErrorSlot(message: generalError),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed:
                        (state.isValid && !state.isVerifying && state.factor != null)
                            ? notifier.verify
                            : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: state.isVerifying
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(l.actionVerify),
                  ),
                ],
              ),
          },
        ),
      ),
    );
  }
}
