import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/core/widgets/pin_code_input.dart';
import 'package:myapp/features/auth/application/mfa_setup_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';

class MfaSetupPage extends ConsumerStatefulWidget {
  const MfaSetupPage({super.key});

  static const double _reservedHeight = 820;

  @override
  ConsumerState<MfaSetupPage> createState() => _MfaSetupPageState();
}

class _MfaSetupPageState extends ConsumerState<MfaSetupPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Iniciar enrollment al entrar (un solo factor por sesión de setup).
      ref.read(mfaSetupNotifierProvider.notifier).startEnrollment(
            friendlyName: 'myapp',
          );
    });
  }

  Future<void> _copySecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    if (!mounted) return;
    context.showSnack(context.l10n.mfaSecretCopied);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mfaSetupNotifierProvider);
    final notifier = ref.read(mfaSetupNotifierProvider.notifier);
    final l = context.l10n;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: MfaSetupPage._reservedHeight,
          leading: Icon(
            Icons.shield_outlined,
            size: 56,
            color: context.colors.primary,
          ),
          title: state.step == MfaSetupStep.done
              ? l.mfaSetupSuccessTitle
              : l.mfaSetupTitle,
          subtitle: state.step == MfaSetupStep.done
              ? l.mfaSetupSuccessSubtitle
              : l.mfaSetupSubtitle,
          child: _body(context, state, notifier, l),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    MfaSetupState state,
    MfaSetupNotifier notifier,
    AppLocalizations l,
  ) {
    switch (state.step) {
      case MfaSetupStep.idle:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        );
      case MfaSetupStep.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.verified_outlined,
              size: 56,
              color: context.colors.tertiary,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.goNamed(RouteNames.home),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(l.actionGoHome),
            ),
          ],
        );
      case MfaSetupStep.qrCode:
      case MfaSetupStep.verifying:
      case MfaSetupStep.failure:
        final enrollment = state.enrollment;
        if (enrollment == null) {
          // Failure antes de tener enrollment (raro): mostrar error +
          // botón para reintentar.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              GeneralErrorSlot(
                message: state.failure != null
                    ? authFailureMessage(context, state.failure!)
                    : l.authErrorUnknown,
              ),
              FilledButton.tonal(
                onPressed: () =>
                    notifier.startEnrollment(friendlyName: 'myapp'),
                child: Text(l.actionContinue),
              ),
            ],
          );
        }
        final generalError = state.failure != null
            ? authFailureMessage(context, state.failure!)
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.mfaSetupStart,
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // QR generado localmente con `qr_flutter` desde el `otpauth://`
            // URI — más fiable que el SVG remoto.
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: enrollment.uri,
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l.mfaSetupSecretLabel,
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Center(
              child: InkWell(
                onTap: () => _copySecret(enrollment.secret),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        enrollment.secret,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.copy_outlined,
                        size: 16,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l.mfaSetupVerifyTitle,
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            PinCodeInput(
              onChanged: notifier.codeChanged,
              onCompleted: (_) => notifier.verify(),
              enabled: state.step != MfaSetupStep.verifying,
              hasError: state.failure != null,
              length: MfaSetupState.codeLength,
            ),
            GeneralErrorSlot(message: generalError),
            const SizedBox(height: 8),
            FilledButton(
              onPressed:
                  state.canSubmit && state.step != MfaSetupStep.verifying
                      ? notifier.verify
                      : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: state.step == MfaSetupStep.verifying
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(l.actionVerify),
            ),
          ],
        );
    }
  }
}
