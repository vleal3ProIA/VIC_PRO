import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/config/env_config.dart';
import 'package:myapp/core/observability/analytics_event.dart';
import 'package:myapp/core/observability/analytics_service.dart';
import 'package:myapp/core/storage/storage_providers.dart';
import 'package:myapp/core/utils/log_context.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/features/audit/domain/audit_events.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum LoginStatus { initial, submitting, success, failure }

enum LoginPasswordError { empty }

/// Para login NO aplicamos las reglas estrictas de Password (mín 8, mayús,
/// etc.) — esas son del registro. En login solo validamos que no esté vacío;
/// si la contraseña no cumple las reglas, el backend devolverá
/// `AuthInvalidCredentials`.
class LoginPasswordInput extends FormzInput<String, LoginPasswordError> {
  const LoginPasswordInput.pure() : super.pure('');
  const LoginPasswordInput.dirty([super.value = '']) : super.dirty();

  @override
  LoginPasswordError? validator(String value) {
    if (value.isEmpty) return LoginPasswordError.empty;
    return null;
  }
}

class LoginState {
  const LoginState({
    this.email = const Email.pure(),
    this.password = const LoginPasswordInput.pure(),
    this.rememberMe = false,
    this.status = LoginStatus.initial,
    this.failure,
    this.showErrors = false,
    this.captchaToken,
  });

  final Email email;
  final LoginPasswordInput password;
  final bool rememberMe;
  final LoginStatus status;
  final AuthFailure? failure;
  final bool showErrors;

  /// Token devuelto por Cloudflare Turnstile. Solo se exige en web con
  /// sitekey configurada (ver [isCaptchaRequired]). Necesario porque
  /// Supabase Auth aplica Bot protection a `/token` (login con password)
  /// además de a `/signup`.
  final String? captchaToken;

  bool get isSubmitting => status == LoginStatus.submitting;

  /// Error de input genérico — el del email se calcula con
  /// `ValidationMessages.email` en la UI. Para password sólo hay "vacío".
  bool get passwordIsEmpty => password.value.isEmpty;

  /// Mismo criterio que en `RegisterState`: solo en builds web reales con
  /// sitekey configurada. Tests (VM) y entornos sin sitekey lo saltan
  /// para no romper login_flow_test ni login_form_test.
  bool get isCaptchaRequired =>
      kIsWeb && EnvConfig.turnstileSitekey.isNotEmpty;

  bool get hasCaptchaToken => captchaToken != null && captchaToken!.isNotEmpty;

  bool get isValid =>
      Formz.validate([email, password]) &&
      (!isCaptchaRequired || hasCaptchaToken);

  LoginState copyWith({
    Email? email,
    LoginPasswordInput? password,
    bool? rememberMe,
    LoginStatus? status,
    AuthFailure? failure,
    bool? showErrors,
    String? captchaToken,
    bool clearFailure = false,
    bool clearCaptchaToken = false,
  }) {
    return LoginState(
      email: email ?? this.email,
      password: password ?? this.password,
      rememberMe: rememberMe ?? this.rememberMe,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      showErrors: showErrors ?? this.showErrors,
      captchaToken:
          clearCaptchaToken ? null : (captchaToken ?? this.captchaToken),
    );
  }
}

class LoginNotifier extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState();

  void emailChanged(String v) {
    state = state.copyWith(
      email: Email.dirty(v.trim()),
      clearFailure: true,
    );
  }

  void passwordChanged(String v) {
    state = state.copyWith(
      password: LoginPasswordInput.dirty(v),
      clearFailure: true,
    );
  }

  void rememberMeChanged({required bool value}) {
    state = state.copyWith(rememberMe: value, clearFailure: true);
  }

  /// Llamado por `TurnstileWidget.onToken` cuando Cloudflare entrega el
  /// token. Habilita el botón "Sign in" (si el resto del form es válido).
  void captchaTokenChanged(String token) {
    state = state.copyWith(captchaToken: token, clearFailure: true);
  }

  /// Llamado cuando el token caduca o el reto falla — deshabilita el
  /// submit hasta que el usuario pase un nuevo reto.
  void captchaTokenCleared() {
    state = state.copyWith(clearCaptchaToken: true);
  }

  Future<void> submit() async {
    state = state.copyWith(showErrors: true, clearFailure: true);
    if (!state.isValid) return;

    // Toda la operación corre dentro de un LogContext único: cualquier log
    // (cliente, auditoría, analytics, Sentry) se asocia al mismo
    // `correlation_id` y a las mismas tags.
    await LogContext.run(
      tags: {'flow': 'login', 'method': 'password'},
      () async {
        final analytics = ref.read(analyticsServiceProvider);
        analytics.trackSync(AnalyticsEvents.loginStarted);

        // Aplicamos la preferencia ANTES del signIn para que la primera
        // llamada a `persistSession` use el backend correcto.
        await ref
            .read(rememberAwareStorageProvider)
            .setRememberMe(value: state.rememberMe);

        state = state.copyWith(status: LoginStatus.submitting);
        final repo = ref.read(authRepositoryProvider);
        final result = await repo.signIn(
          email: state.email.value.trim(),
          password: state.password.value,
          captchaToken: state.captchaToken,
        );
        result.match(
          (failure) {
            state = state.copyWith(
              status: LoginStatus.failure,
              failure: failure,
            );
            analytics.trackSync(
              AnalyticsEvents.loginFailed,
              properties: {'reason': failure.runtimeType.toString()},
            );
          },
          (_) {
            state = state.copyWith(status: LoginStatus.success);
            // Audit trail (fire-and-forget; no bloquea el flujo de login).
            ref.read(auditLoggerProvider).log(AuditEvents.loginPassword);
            analytics.trackSync(AnalyticsEvents.loginSucceeded);
          },
        );
      },
    );
  }

  void reset() => state = const LoginState();
}

final loginNotifierProvider =
    NotifierProvider<LoginNotifier, LoginState>(LoginNotifier.new);
