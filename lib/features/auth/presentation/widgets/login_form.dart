import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/core/validation/validation_messages.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/features/auth/application/login_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';

class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  late final TextEditingController _email;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController();
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginNotifierProvider);
    final notifier = ref.read(loginNotifierProvider.notifier);
    final l = context.l10n;

    String? errOrNull({required bool show, required String? msg}) =>
        show ? msg : null;
    final showErrors = state.showErrors;

    final emailError = errOrNull(
      show: showErrors || !state.email.isPure,
      msg: ValidationMessages.email(context, state.email.displayError),
    );
    final passwordError = errOrNull(
      show: showErrors && state.passwordIsEmpty,
      msg: l.errorRequired,
    );

    final generalError = state.failure != null
        ? authFailureMessage(context, state.failure!)
        : null;

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _email,
            label: l.fieldEmail,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            maxLength: Email.maxLength,
            errorText: emailError,
            onChanged: notifier.emailChanged,
            enabled: !state.isSubmitting,
          ),
          AppTextField(
            controller: _password,
            label: l.fieldPassword,
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            errorText: passwordError,
            onChanged: notifier.passwordChanged,
            onSubmitted: (_) => notifier.submit(),
            enabled: !state.isSubmitting,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: state.isSubmitting
                  ? null
                  : () => context.goNamed(RouteNames.forgotPassword),
              child: Text(l.loginForgotPassword),
            ),
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
                : Text(l.actionSignIn),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(l.loginNoAccount, style: context.textTheme.bodyMedium),
              const SizedBox(width: 4),
              TextButton(
                onPressed: state.isSubmitting
                    ? null
                    : () => context.goNamed(RouteNames.register),
                child: Text(l.loginCreateOne),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
