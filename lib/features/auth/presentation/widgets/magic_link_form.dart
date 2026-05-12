import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/core/validation/validation_messages.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/features/auth/application/magic_link_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';

class MagicLinkForm extends ConsumerStatefulWidget {
  const MagicLinkForm({super.key});

  @override
  ConsumerState<MagicLinkForm> createState() => _MagicLinkFormState();
}

class _MagicLinkFormState extends ConsumerState<MagicLinkForm> {
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
    ref.listen<MagicLinkState>(magicLinkNotifierProvider, (prev, next) {
      if (prev?.status != MagicLinkStatus.success &&
          next.status == MagicLinkStatus.success &&
          next.sentToEmail != null) {
        context.goNamed(
          RouteNames.magicLinkSent,
          queryParameters: {'email': next.sentToEmail ?? ''},
        );
      }
    });

    final state = ref.watch(magicLinkNotifierProvider);
    final notifier = ref.read(magicLinkNotifierProvider.notifier);
    final l = context.l10n;

    String? errOrNull({required bool show, required String? msg}) =>
        show ? msg : null;

    final emailError = errOrNull(
      show: state.showErrors || !state.email.isPure,
      msg: ValidationMessages.email(context, state.email.displayError),
    );

    final generalError = state.failure != null
        ? authFailureMessage(context, state.failure!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: _email,
          label: l.fieldEmail,
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
              : Text(l.actionSendMagicLink),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: state.isSubmitting
              ? null
              : () => context.goNamed(RouteNames.login),
          child: Text(l.actionUsePassword),
        ),
      ],
    );
  }
}
