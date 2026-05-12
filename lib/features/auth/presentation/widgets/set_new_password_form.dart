import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/validation/validation_messages.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/features/auth/application/password_update_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';

class SetNewPasswordForm extends ConsumerStatefulWidget {
  const SetNewPasswordForm({super.key});

  @override
  ConsumerState<SetNewPasswordForm> createState() => _SetNewPasswordFormState();
}

class _SetNewPasswordFormState extends ConsumerState<SetNewPasswordForm> {
  late final TextEditingController _password;
  late final TextEditingController _confirmation;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController();
    _confirmation = TextEditingController();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PasswordUpdateState>(passwordUpdateNotifierProvider,
        (prev, next) {
      if (prev?.status != PasswordUpdateStatus.success &&
          next.status == PasswordUpdateStatus.success) {
        context.goNamed(RouteNames.passwordUpdated);
      }
    });

    final state = ref.watch(passwordUpdateNotifierProvider);
    final notifier = ref.read(passwordUpdateNotifierProvider.notifier);
    final l = context.l10n;
    final showErrors = state.showErrors;

    String? errOrNull({required bool show, required String? msg}) =>
        show ? msg : null;

    final passwordError = errOrNull(
      show: showErrors || !state.password.isPure,
      msg: ValidationMessages.password(context, state.password.displayError),
    );
    final confirmError = errOrNull(
      show: showErrors || !state.confirmation.isPure,
      msg: ValidationMessages.passwordConfirmation(
        context,
        state.confirmation.displayError,
      ),
    );
    final generalError = state.failure != null
        ? authFailureMessage(context, state.failure!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: _password,
          label: l.fieldNewPassword,
          prefixIcon: Icons.lock_outline,
          isPassword: true,
          autofillHints: const [AutofillHints.newPassword],
          errorText: passwordError,
          onChanged: notifier.passwordChanged,
          enabled: !state.isSubmitting,
        ),
        AppTextField(
          controller: _confirmation,
          label: l.fieldPasswordConfirm,
          prefixIcon: Icons.lock_outline,
          isPassword: true,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          errorText: confirmError,
          onChanged: notifier.confirmationChanged,
          onSubmitted: (_) => notifier.submit(),
          enabled: !state.isSubmitting,
        ),
        GeneralErrorSlot(message: generalError),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: state.isSubmitting ? null : notifier.submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: state.isSubmitting
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Text(l.actionUpdatePassword),
        ),
      ],
    );
  }
}
