import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/core/widgets/info_banner.dart';
import 'package:myapp/features/auth/application/account_deletion_notifier.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

class DeleteAccountForm extends ConsumerStatefulWidget {
  const DeleteAccountForm({super.key});

  @override
  ConsumerState<DeleteAccountForm> createState() => _DeleteAccountFormState();
}

class _DeleteAccountFormState extends ConsumerState<DeleteAccountForm> {
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _onDeletePressed() async {
    final notifier = ref.read(accountDeletionNotifierProvider.notifier);
    final state = ref.read(accountDeletionNotifierProvider);
    final l = context.l10n;

    // Si falta algo (contraseña o casilla), `submit` activa los errores y
    // retorna sin tocar el backend.
    if (!state.isValid) {
      await notifier.submit();
      return;
    }

    // Diálogo de confirmación final: última barrera antes del borrado.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteAccountConfirmTitle),
        content: Text(l.deleteAccountConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.error,
              foregroundColor: ctx.colors.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.actionDeleteAccount),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await notifier.submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AccountDeletionState>(accountDeletionNotifierProvider,
        (prev, next) {
      if (prev?.status != AccountDeletionStatus.success &&
          next.status == AccountDeletionStatus.success) {
        // La sesión ya está cerrada por el repositorio; volvemos al inicio.
        context.showSnack(context.l10n.deleteAccountDone);
        context.goNamed(RouteNames.welcome);
      }
    });

    final state = ref.watch(accountDeletionNotifierProvider);
    final notifier = ref.read(accountDeletionNotifierProvider.notifier);
    final l = context.l10n;

    final passwordError = state.showErrors && state.passwordIsEmpty
        ? l.errorRequired
        : null;

    String? generalError;
    if (state.failure != null) {
      generalError = switch (state.failure!) {
        AuthInvalidCredentials() => l.authErrorCurrentPasswordWrong,
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
          InfoBanner(
            message: l.deleteAccountWarning,
            kind: InfoBannerKind.warning,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _password,
            label: l.fieldCurrentPassword,
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            errorText: passwordError,
            onChanged: notifier.passwordChanged,
            enabled: !state.isSubmitting,
          ),
          InkWell(
            onTap: state.isSubmitting
                ? null
                : () => notifier.acknowledgedChanged(
                      value: !state.acknowledged,
                    ),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: state.acknowledged,
                    onChanged: state.isSubmitting
                        ? null
                        : (v) => notifier.acknowledgedChanged(
                              value: v ?? false,
                            ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        l.deleteAccountAcknowledge,
                        style: context.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          GeneralErrorSlot(message: generalError),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: state.isSubmitting ? null : _onDeletePressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
            ),
            child: state.isSubmitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Text(l.actionDeleteAccount),
          ),
        ],
      ),
    );
  }
}
