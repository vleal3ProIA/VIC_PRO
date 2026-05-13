import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/core/widgets/pin_code_input.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/otp_verify_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';

class OtpVerifyForm extends ConsumerStatefulWidget {
  const OtpVerifyForm({required this.email, super.key});

  final String email;

  @override
  ConsumerState<OtpVerifyForm> createState() => _OtpVerifyFormState();
}

class _OtpVerifyFormState extends ConsumerState<OtpVerifyForm> {
  bool _resending = false;

  Future<void> _resend() async {
    setState(() => _resending = true);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.requestEmailOtp(widget.email);
    if (!mounted) return;
    result.match(
      (failure) => context.showSnack(
        authFailureMessage(context, failure),
        isError: true,
      ),
      (_) => context.showSnack(context.l10n.otpResent),
    );
    setState(() => _resending = false);
  }

  @override
  Widget build(BuildContext context) {
    final familyProvider = otpVerifyNotifierProvider(widget.email);

    // Nota: NO navegamos manualmente al éxito. Cuando `verifyEmailOtp`
    // abre sesión, el `authStateChangesProvider` emite, el router refresca
    // y los guards detectan `/otp-verify` ∈ _publicOnly + isAuthed=true →
    // redirige a /home automáticamente. Hacerlo manualmente aquí dispara
    // una race con el guard que puede acabar empujando al usuario a /login.

    final state = ref.watch(familyProvider);
    final notifier = ref.read(familyProvider.notifier);
    final l = context.l10n;

    final generalError = state.failure != null
        ? authFailureMessage(context, state.failure!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.otpHint(state.codeLength),
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        PinCodeInput(
          onChanged: notifier.codeChanged,
          onCompleted: (_) => notifier.submit(),
          enabled: !state.isSubmitting,
          hasError: state.failure != null,
          length: state.codeLength,
        ),
        GeneralErrorSlot(message: generalError),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: (state.isSubmitting || !state.isValid)
              ? null
              : notifier.submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: state.isSubmitting
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Text(l.actionVerifyOtp),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resending ? null : _resend,
          child: _resending
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.actionResend),
        ),
      ],
    );
  }
}
