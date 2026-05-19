import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/core/validation/validation_messages.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/core/widgets/reauth_dialog.dart';
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

  /// Pide re-auth (password reciente) ANTES de invocar el cambio de
  /// email. Si el user cancela el dialog o el password es incorrecto,
  /// el notifier ni siquiera se ejecuta -- la sesion robada no podra
  /// disparar este flow sin la password real.
  ///
  /// Limitacion conocida: la verificacion es client-side. Un atacante
  /// determinado con JWT robado puede invocar `supabase.auth.updateUser`
  /// directamente. Bloquear ese path requeriria una Edge Function
  /// intermediaria `change-email` que consuma una recent_verification
  /// server-side (TODO en un PR futuro). El dialog corta el ataque
  /// realista: cookies XSS, sesiones compartidas, dispositivos
  /// prestados.
  Future<void> _onSubmit() async {
    // 1) Validar el form ANTES de abrir el dialog -- no queremos
    //    enseyar el modal de password si el email esta vacio o mal
    //    escrito.
    final notifier = ref.read(changeEmailNotifierProvider.notifier);
    if (!notifier.validateForm()) return;

    // 2) Re-auth gate. Si el user cancela o el password es incorrecto,
    //    no se llama a `submit()` y por tanto no se invoca
    //    `supabase.auth.updateUser`. Esto bloquea el ataque "robo de
    //    cookie + cambio de email" desde el browser.
    final ok = await ReauthDialog.show(
      context,
      ref: ref,
      actionKind: 'change_email',
    );
    if (ok != true || !mounted) return;

    // 3) Ya validado + re-auth fresca -- disparar el cambio.
    await notifier.submit();
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
          onSubmitted: (_) => _onSubmit(),
          enabled: !state.isSubmitting,
        ),
        GeneralErrorSlot(message: generalError),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: state.isSubmitting ? null : _onSubmit,
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
