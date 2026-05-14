import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/validation/validation_messages.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/features/auth/application/change_password_notifier.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

class ChangePasswordForm extends ConsumerStatefulWidget {
  const ChangePasswordForm({super.key});

  @override
  ConsumerState<ChangePasswordForm> createState() =>
      _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<ChangePasswordForm> {
  late final TextEditingController _current;
  late final TextEditingController _new;
  late final TextEditingController _confirm;

  @override
  void initState() {
    super.initState();
    _current = TextEditingController();
    _new = TextEditingController();
    _confirm = TextEditingController();
  }

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChangePasswordState>(changePasswordNotifierProvider,
        (prev, next) {
      if (prev?.status != ChangePasswordStatus.success &&
          next.status == ChangePasswordStatus.success) {
        context.goNamed(RouteNames.changePasswordDone);
      }
    });

    final state = ref.watch(changePasswordNotifierProvider);
    final notifier = ref.read(changePasswordNotifierProvider.notifier);
    final l = context.l10n;
    final show = state.showErrors;

    String? errOrNull({required bool when, required String? msg}) =>
        when ? msg : null;

    final currentError = errOrNull(
      when: show && state.currentIsEmpty,
      msg: l.errorRequired,
    );
    final newError = errOrNull(
      when: show || !state.newPassword.isPure,
      msg: ValidationMessages.password(
        context,
        state.newPassword.displayError,
      ),
    );
    final confirmError = errOrNull(
      when: show || !state.confirmation.isPure,
      msg: ValidationMessages.passwordConfirmation(
        context,
        state.confirmation.displayError,
      ),
    );

    // El failure de reautenticación llega como AuthInvalidCredentials;
    // en este contexto significa "contraseña actual incorrecta".
    String? generalError;
    if (state.failure != null) {
      generalError = switch (state.failure!) {
        AuthInvalidCredentials() => l.authErrorCurrentPasswordWrong,
        AuthWeakPassword() => l.authErrorWeakPassword,
        AuthRateLimited() => l.authErrorRateLimited,
        AuthNetworkError() => l.authErrorNetwork,
        _ => l.authErrorUnknown,
      };
    }

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _current,
            label: l.fieldCurrentPassword,
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            autofillHints: const [AutofillHints.password],
            errorText: currentError,
            onChanged: notifier.currentPasswordChanged,
            enabled: !state.isSubmitting,
          ),
          AppTextField(
            controller: _new,
            label: l.fieldNewPassword,
            prefixIcon: Icons.lock_reset_outlined,
            isPassword: true,
            autofillHints: const [AutofillHints.newPassword],
            errorText: newError,
            onChanged: notifier.newPasswordChanged,
            enabled: !state.isSubmitting,
          ),
          AppTextField(
            controller: _confirm,
            label: l.fieldPasswordConfirm,
            prefixIcon: Icons.lock_reset_outlined,
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
      ),
    );
  }
}
