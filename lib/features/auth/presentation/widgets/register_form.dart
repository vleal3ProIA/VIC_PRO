import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/core/validation/validation_messages.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/features/auth/application/oauth_notifier.dart';
import 'package:myapp/features/auth/application/register_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';
import 'package:myapp/features/auth/presentation/widgets/social_sign_in_button.dart';

class RegisterForm extends ConsumerStatefulWidget {
  const RegisterForm({super.key});

  @override
  ConsumerState<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends ConsumerState<RegisterForm> {
  late final TextEditingController _username;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late final TextEditingController _passwordConfirm;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController();
    _email = TextEditingController();
    _password = TextEditingController();
    _passwordConfirm = TextEditingController();
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  void _navigateToVerificationSent(String email) {
    // pushReplacement para evitar volver al formulario con back.
    context.goNamed(
      RouteNames.verifyEmailSent,
      queryParameters: {'email': email},
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reaccionar a éxito del submit.
    ref.listen<RegisterState>(registerNotifierProvider, (prev, next) {
      if (prev?.status != RegisterStatus.success &&
          next.status == RegisterStatus.success &&
          next.signedUpEmail != null) {
        _navigateToVerificationSent(next.signedUpEmail!);
      }
    });

    final state = ref.watch(registerNotifierProvider);
    final notifier = ref.read(registerNotifierProvider.notifier);
    final oauthState = ref.watch(oauthNotifierProvider);
    final oauthNotifier = ref.read(oauthNotifierProvider.notifier);
    final l = context.l10n;

    final busy = state.isSubmitting || oauthState.isBusy;

    String? errOrNull({required bool show, required String? msg}) =>
        show ? msg : null;
    final showErrors = state.showErrors;

    final usernameError = errOrNull(
      show: showErrors || !state.username.isPure,
      msg: ValidationMessages.username(context, state.username.displayError),
    );
    final emailError = errOrNull(
      show: showErrors || !state.email.isPure,
      msg: ValidationMessages.email(context, state.email.displayError),
    );
    final passwordError = errOrNull(
      show: showErrors || !state.password.isPure,
      msg: ValidationMessages.password(context, state.password.displayError),
    );
    final confirmError = errOrNull(
      show: showErrors || !state.passwordConfirmation.isPure,
      msg: ValidationMessages.passwordConfirmation(
        context,
        state.passwordConfirmation.displayError,
      ),
    );

    // General error: failure del backend o "debe aceptar términos" si pulsó submit.
    String? generalError;
    if (state.failure != null) {
      generalError = authFailureMessage(context, state.failure!);
    } else if (oauthState.failure != null) {
      generalError = authFailureMessage(context, oauthState.failure!);
    } else if (showErrors && !state.acceptTerms) {
      generalError = l.errorAcceptTerms;
    }

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _username,
            label: l.fieldUsername,
            prefixIcon: Icons.alternate_email,
            keyboardType: TextInputType.text,
            autofillHints: const [AutofillHints.username, AutofillHints.newUsername],
            errorText: usernameError,
            onChanged: notifier.usernameChanged,
            enabled: !state.isSubmitting,
          ),
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
            autofillHints: const [AutofillHints.newPassword],
            errorText: passwordError,
            onChanged: notifier.passwordChanged,
            enabled: !state.isSubmitting,
          ),
          AppTextField(
            controller: _passwordConfirm,
            label: l.fieldPasswordConfirm,
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            errorText: confirmError,
            onChanged: notifier.passwordConfirmationChanged,
            onSubmitted: (_) => notifier.submit(),
            enabled: !state.isSubmitting,
          ),
          // Espacio reservado para errores generales (no mueve la card).
          GeneralErrorSlot(message: generalError),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: state.acceptTerms,
                onChanged: state.isSubmitting
                    ? null
                    : (v) => notifier.acceptTermsChanged(value: v ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.registerAcceptTerms,
                        style: context.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 16,
                        children: [
                          _LegalLink(
                            label: l.termsTitle,
                            routeName: RouteNames.terms,
                          ),
                          _LegalLink(
                            label: l.privacyTitle,
                            routeName: RouteNames.privacy,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : notifier.submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: state.isSubmitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Text(l.actionCreateAccount),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  l.loginOrDivider,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 8),
          SocialSignInButton(
            label: l.continueWithGoogle,
            iconAsset: 'assets/icons/google.svg',
            busy: oauthState.isBusyWith(SocialProvider.google),
            onPressed: busy
                ? null
                : () => oauthNotifier.signIn(SocialProvider.google),
          ),
          const SizedBox(height: 8),
          SocialSignInButton(
            label: l.continueWithApple,
            iconAsset: 'assets/icons/apple.svg',
            iconColor: context.colors.onSurface,
            busy: oauthState.isBusyWith(SocialProvider.apple),
            onPressed: busy
                ? null
                : () => oauthNotifier.signIn(SocialProvider.apple),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l.registerHaveAccount,
                style: context.textTheme.bodyMedium,
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: busy
                    ? null
                    : () => context.goNamed(RouteNames.login),
                child: Text(l.actionSignIn),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Enlace compacto a un documento legal (`/terms`, `/privacy`).
class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.routeName});

  final String label;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.goNamed(routeName),
      borderRadius: BorderRadius.circular(4),
      child: Text(
        label,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colors.primary,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: context.colors.primary,
        ),
      ),
    );
  }
}
