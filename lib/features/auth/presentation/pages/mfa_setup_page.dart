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

class MfaSetupPage extends ConsumerWidget {
  const MfaSetupPage({super.key});

  static const double _reservedHeight = 820;

  Future<void> _copySecret(BuildContext context, String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    if (!context.mounted) return;
    context.showSnack(context.l10n.mfaSecretCopied);
  }

  Future<void> _confirmDisable(
    BuildContext context,
    MfaSetupNotifier notifier,
  ) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.mfaDisableConfirmTitle),
        content: Text(l.mfaDisableConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.actionDisableMfa),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await notifier.disable();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mfaSetupNotifierProvider);
    final notifier = ref.read(mfaSetupNotifierProvider.notifier);
    final l = context.l10n;

    final (title, subtitle) = switch (state.step) {
      MfaSetupStep.alreadyEnabled => (
          l.mfaAlreadyEnabledTitle,
          l.mfaAlreadyEnabledSubtitle,
        ),
      MfaSetupStep.done => (
          l.mfaSetupSuccessTitle,
          l.mfaSetupSuccessSubtitle,
        ),
      MfaSetupStep.disabled => (
          l.mfaDisabledTitle,
          l.mfaDisabledSubtitle,
        ),
      _ => (l.mfaSetupTitle, l.mfaSetupSubtitle),
    };

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          leading: Icon(
            Icons.shield_outlined,
            size: 56,
            color: context.colors.primary,
          ),
          title: title,
          subtitle: subtitle,
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
      case MfaSetupStep.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                l.mfaCheckingStatus,
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );

      case MfaSetupStep.alreadyEnabled:
      case MfaSetupStep.unenrolling:
        final disabling = state.step == MfaSetupStep.unenrolling;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Icon(
              Icons.verified_user_outlined,
              size: 56,
              color: context.colors.tertiary,
            ),
            GeneralErrorSlot(
              message: state.failure != null
                  ? authFailureMessage(context, state.failure!)
                  : null,
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.error,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: disabling
                  ? null
                  : () => _confirmDisable(context, notifier),
              child: disabling
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(l.actionDisableMfa),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.goNamed(RouteNames.home),
              child: Text(l.actionGoHome),
            ),
          ],
        );

      case MfaSetupStep.disabled:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.gpp_maybe_outlined,
              size: 56,
              color: context.colors.onSurfaceVariant,
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
                onPressed: notifier.retryEnrollment,
                child: Text(l.actionRetry),
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
                onTap: () => _copySecret(context, enrollment.secret),
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
