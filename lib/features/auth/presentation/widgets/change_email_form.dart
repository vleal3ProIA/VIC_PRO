import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/core/validation/validation_messages.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/features/auth/application/change_email_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';

class ChangeEmailForm extends ConsumerStatefulWidget {
  const ChangeEmailForm({super.key});

  @override
  ConsumerState<ChangeEmailForm> createState() => _ChangeEmailFormState();
}

class _ChangeEmailFormState extends ConsumerState<ChangeEmailForm> {
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChangeEmailState>(changeEmailNotifierProvider, (prev, next) {
      if (prev?.status != ChangeEmailStatus.success &&
          next.status == ChangeEmailStatus.success &&
          next.sentToEmail != null) {
        context.goNamed(
          RouteNames.changeEmailSent,
          queryParameters: {'email': next.sentToEmail ?? ''},
        );
      }
    });

    final state = ref.watch(changeEmailNotifierProvider);
    final notifier = ref.read(changeEmailNotifierProvider.notifier);
    final l = context.l10n;

    final emailError = (state.showErrors || !state.newEmail.isPure)
        ? ValidationMessages.email(context, state.newEmail.displayError)
        : null;
    final generalError = state.failure != null
        ? authFailureMessage(context, state.failure!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: _email,
          label: l.fieldNewEmail,
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          maxLength: Email.maxLength,
          errorText: emailError,
          onChanged: notifier.emailChanged,
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
              : Text(l.actionContinue),
        ),
      ],
    );
  }
}
