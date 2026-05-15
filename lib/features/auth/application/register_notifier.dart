import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/observability/analytics_event.dart';
import 'package:myapp/core/observability/analytics_service.dart';
import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/core/utils/log_context.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/core/validation/password.dart';
import 'package:myapp/core/validation/password_confirmation.dart';
import 'package:myapp/core/validation/username.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/entities/sign_up_request.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum RegisterStatus { initial, submitting, success, failure }

class RegisterState {
  const RegisterState({
    this.username = const Username.pure(),
    this.email = const Email.pure(),
    this.password = const Password.pure(),
    this.passwordConfirmation = const PasswordConfirmation.pure(),
    this.acceptTerms = false,
    this.status = RegisterStatus.initial,
    this.failure,
    this.signedUpEmail,
    this.showErrors = false,
  });

  final Username username;
  final Email email;
  final Password password;
  final PasswordConfirmation passwordConfirmation;
  final bool acceptTerms;
  final RegisterStatus status;
  final AuthFailure? failure;
  final String? signedUpEmail;

  /// Cuando es `true`, los inputs muestran sus errores aunque estén `pure`
  /// (se activa al pulsar Submit la primera vez).
  final bool showErrors;

  bool get isValid =>
      Formz.validate([username, email, password, passwordConfirmation]) &&
      acceptTerms;

  bool get isSubmitting => status == RegisterStatus.submitting;

  RegisterState copyWith({
    Username? username,
    Email? email,
    Password? password,
    PasswordConfirmation? passwordConfirmation,
    bool? acceptTerms,
    RegisterStatus? status,
    AuthFailure? failure,
    String? signedUpEmail,
    bool? showErrors,
    bool clearFailure = false,
  }) {
    return RegisterState(
      username: username ?? this.username,
      email: email ?? this.email,
      password: password ?? this.password,
      passwordConfirmation: passwordConfirmation ?? this.passwordConfirmation,
      acceptTerms: acceptTerms ?? this.acceptTerms,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      signedUpEmail: signedUpEmail ?? this.signedUpEmail,
      showErrors: showErrors ?? this.showErrors,
    );
  }
}

class RegisterNotifier extends Notifier<RegisterState> {
  @override
  RegisterState build() => const RegisterState();

  void usernameChanged(String v) {
    state = state.copyWith(
      username: Username.dirty(v),
      clearFailure: true,
    );
  }

  void emailChanged(String v) {
    state = state.copyWith(
      email: Email.dirty(v.trim()),
      clearFailure: true,
    );
  }

  void passwordChanged(String v) {
    final pwd = Password.dirty(v);
    // Re-validar confirmation con el nuevo valor.
    final conf = PasswordConfirmation.dirty(
      password: v,
      value: state.passwordConfirmation.value,
    );
    state = state.copyWith(
      password: pwd,
      passwordConfirmation: conf,
      clearFailure: true,
    );
  }

  void passwordConfirmationChanged(String v) {
    state = state.copyWith(
      passwordConfirmation: PasswordConfirmation.dirty(
        password: state.password.value,
        value: v,
      ),
      clearFailure: true,
    );
  }

  void acceptTermsChanged({required bool value}) {
    state = state.copyWith(acceptTerms: value, clearFailure: true);
  }

  Future<void> submit() async {
    state = state.copyWith(showErrors: true, clearFailure: true);
    if (!state.isValid) return;

    await LogContext.run(
      tags: {'flow': 'signup'},
      () async {
        final analytics = ref.read(analyticsServiceProvider);
        analytics.trackSync(AnalyticsEvents.signupStarted);

        state = state.copyWith(status: RegisterStatus.submitting);

        // Idioma y tema que el usuario está viendo ahora mismo: viajan en el
        // signUp para que su perfil se cree con estas preferencias y el
        // primer login no le cambie el idioma a 'en'.
        final locale = ref.read(effectiveLocaleProvider).languageCode;
        final themeMode = ref.read(themeNotifierProvider).name;

        final repo = ref.read(authRepositoryProvider);
        final result = await repo.signUp(
          SignUpRequest(
            username: state.username.value.trim(),
            email: state.email.value.trim(),
            password: state.password.value,
            locale: locale,
            themeMode: themeMode,
          ),
        );
        result.match(
          (failure) {
            state = state.copyWith(
              status: RegisterStatus.failure,
              failure: failure,
            );
            analytics.trackSync(
              AnalyticsEvents.signupFailed,
              properties: {'reason': failure.runtimeType.toString()},
            );
          },
          (ok) {
            state = state.copyWith(
              status: RegisterStatus.success,
              signedUpEmail: ok.email,
            );
            analytics.trackSync(
              AnalyticsEvents.signupSucceeded,
              properties: {
                'needs_email_confirmation': ok.needsEmailConfirmation,
              },
            );
          },
        );
      },
    );
  }

  void reset() => state = const RegisterState();
}

final registerNotifierProvider =
    NotifierProvider<RegisterNotifier, RegisterState>(RegisterNotifier.new);
