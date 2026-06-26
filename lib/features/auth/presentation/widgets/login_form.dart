import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/core/validation/validation_messages.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';
import 'package:myapp/features/auth/application/login_notifier.dart';
import 'package:myapp/features/auth/application/oauth_notifier.dart';
import 'package:myapp/features/auth/application/passkey_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';
import 'package:myapp/features/auth/presentation/widgets/social_sign_in_button.dart';
import 'package:myapp/features/auth/presentation/widgets/turnstile_widget.dart';
import 'package:myapp/features/branding/application/branding_providers.dart';

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
    // Navegación explícita al hacer login con éxito. No dependemos solo del
    // guard del router: el evento de `onAuthStateChange` llega de forma
    // asíncrona y podía retrasar (o, combinado con rebuilds, "perder") la
    // primera navegación —de ahí el "hay que pulsar dos veces". Al navegar
    // aquí, el guard de `/home` lee la sesión fresca del cliente y la deja
    // pasar.
    ref.listen<LoginState>(loginNotifierProvider, (prev, next) {
      if (prev?.status != LoginStatus.success &&
          next.status == LoginStatus.success) {
        context.goNamed(RouteNames.home);
      }
    });

    // Tras un login con passkey, navegamos también explícitamente (la
    // sesión ya está minteada, el guard de /home la verá fresca).
    ref.listen<PasskeyActionState>(passkeyNotifierProvider, (prev, next) {
      if (prev?.status != PasskeyActionStatus.success &&
          next.status == PasskeyActionStatus.success) {
        context.goNamed(RouteNames.home);
      }
    });

    final state = ref.watch(loginNotifierProvider);
    final notifier = ref.read(loginNotifierProvider.notifier);
    final oauthState = ref.watch(oauthNotifierProvider);
    final oauthNotifier = ref.read(oauthNotifierProvider.notifier);
    final passkeyState = ref.watch(passkeyNotifierProvider);
    final passkeyNotifier = ref.read(passkeyNotifierProvider.notifier);
    final l = context.l10n;

    // Métodos de login alternativos activos (el admin los gestiona desde
    // /admin/app-branding). Email+contraseña es base y siempre está.
    final branding = ref.watch(brandingOrFallbackProvider);
    final hasAltMethods = branding.authGoogleEnabled ||
        branding.authAppleEnabled ||
        branding.authMagicLinkEnabled ||
        branding.authOtpEnabled ||
        branding.authPasskeyEnabled;

    // Cualquier acción en curso (login con password, OAuth, passkey) bloquea
    // el resto de botones para evitar disparos simultáneos.
    final busy = state.isSubmitting || oauthState.isBusy || passkeyState.isBusy;

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

    // Causa local que bloquea el submit (captcha pendiente) solo se
    // muestra si no hay error del backend que sea más informativo.
    String? generalError;
    if (state.failure != null) {
      generalError = authFailureMessage(context, state.failure!);
    } else if (oauthState.failure != null) {
      generalError = authFailureMessage(context, oauthState.failure!);
    } else if (showErrors &&
        state.isCaptchaRequired &&
        !state.hasCaptchaToken) {
      generalError = l.registerCaptchaPending;
    }

    // Mismo gating que en RegisterForm: en web con sitekey configurada,
    // exige token de Turnstile antes de habilitar el submit. En tests
    // (VM) `isCaptchaRequired` es false → no rompe login_flow_test.
    final captchaBlocks =
        state.isCaptchaRequired && !state.hasCaptchaToken;
    final submitDisabled = busy || captchaBlocks;

    // NOTA: NO usamos AutofillGroup ni autofillHints en el login. El
    // navegador autocompletaba la contraseña (a veces de otra cuenta) al
    // escribir el email, lo que confundía al usuario. Sin autofill, los
    // campos solo se rellenan si el usuario escribe.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: _email,
          label: l.fieldEmail,
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
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
          // Marcamos el campo como `new-password` (autocomplete="new-password"
          // en web): es el señuelo estándar para que Chrome/Safari NO
          // autocompleten una contraseña guardada (a veces de otra cuenta) al
          // escribir el email. El usuario escribe su contraseña a mano.
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          errorText: passwordError,
          onChanged: notifier.passwordChanged,
          onSubmitted: (_) => notifier.submit(),
          enabled: !state.isSubmitting,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: state.isSubmitting
                  ? null
                  : () => notifier.rememberMeChanged(
                        value: !state.rememberMe,
                      ),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: state.rememberMe,
                      onChanged: state.isSubmitting
                          ? null
                          : (v) => notifier.rememberMeChanged(
                                value: v ?? false,
                              ),
                    ),
                    Text(
                      l.actionRememberMe,
                      style: context.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: state.isSubmitting
                  ? null
                  : () => context.goNamed(RouteNames.forgotPassword),
              child: Text(l.loginForgotPassword),
            ),
          ],
        ),
        GeneralErrorSlot(message: generalError),
        const SizedBox(height: 8),
        // Captcha Turnstile. SOLO renderiza en web con sitekey
        // configurada; en tests devuelve SizedBox.shrink. Necesario
        // porque Supabase Auth aplica Bot protection a `/token` (login
        // con password), no solo a `/signup`.
        TurnstileWidget(
          languageCode: ref.watch(effectiveLocaleProvider).languageCode,
          onToken: notifier.captchaTokenChanged,
          onExpired: notifier.captchaTokenCleared,
          onError: (_) => notifier.captchaTokenCleared(),
        ),
        if (state.isCaptchaRequired) const SizedBox(height: 8),
        FilledButton(
          onPressed: submitDisabled ? null : notifier.submit,
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
        if (hasAltMethods) ...[
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
          const SizedBox(height: 12),
          // Métodos alternativos compactos: una fila de iconos (con tooltip)
          // en vez de 5 botones a ancho completo. Cada método se muestra solo
          // si está activado por el admin en /admin/app-branding.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (branding.authPasskeyEnabled)
                _AltAuthButton(
                  icon: Icons.fingerprint,
                  tooltip: l.loginWithPasskey,
                  busy: passkeyState.isBusy,
                  onPressed: busy ? null : passkeyNotifier.login,
                ),
              if (branding.authGoogleEnabled)
                SocialSignInButton(
                  label: l.continueWithGoogle,
                  iconAsset: 'assets/icons/google.svg',
                  iconOnly: true,
                  busy: oauthState.isBusyWith(SocialProvider.google),
                  onPressed: busy
                      ? null
                      : () => oauthNotifier.signIn(SocialProvider.google),
                ),
              if (branding.authAppleEnabled)
                SocialSignInButton(
                  label: l.continueWithApple,
                  iconAsset: 'assets/icons/apple.svg',
                  iconColor: context.colors.onSurface,
                  iconOnly: true,
                  busy: oauthState.isBusyWith(SocialProvider.apple),
                  onPressed: busy
                      ? null
                      : () => oauthNotifier.signIn(SocialProvider.apple),
                ),
              if (branding.authMagicLinkEnabled)
                _AltAuthButton(
                  icon: Icons.auto_awesome_outlined,
                  tooltip: l.loginWithMagicLink,
                  onPressed:
                      busy ? null : () => context.goNamed(RouteNames.magicLink),
                ),
              if (branding.authOtpEnabled)
                _AltAuthButton(
                  icon: Icons.pin_outlined,
                  tooltip: l.loginWithOtp,
                  onPressed: busy
                      ? null
                      : () => context.goNamed(RouteNames.otpRequest),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l.loginNoAccount, style: context.textTheme.bodyMedium),
            const SizedBox(width: 4),
            TextButton(
              onPressed:
                  busy ? null : () => context.goNamed(RouteNames.register),
              child: Text(l.loginCreateOne),
            ),
          ],
        ),
      ],
    );
  }
}

/// Botón compacto (cuadrado, solo icono + tooltip) para un método de login
/// alternativo en la fila del login (passkey, magic link, OTP…).
class _AltAuthButton extends StatelessWidget {
  const _AltAuthButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(56, 48),
          padding: EdgeInsets.zero,
        ),
        child: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Icon(icon, size: 20),
      ),
    );
  }
}
