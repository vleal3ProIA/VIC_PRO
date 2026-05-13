import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/storage/storage_providers.dart';
import 'package:myapp/core/validation/email.dart';
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
  });

  final Email email;
  final LoginPasswordInput password;
  final bool rememberMe;
  final LoginStatus status;
  final AuthFailure? failure;
  final bool showErrors;

  bool get isValid => Formz.validate([email, password]);
  bool get isSubmitting => status == LoginStatus.submitting;

  /// Error de input genérico — el del email se calcula con
  /// `ValidationMessages.email` en la UI. Para password sólo hay "vacío".
  bool get passwordIsEmpty => password.value.isEmpty;

  LoginState copyWith({
    Email? email,
    LoginPasswordInput? password,
    bool? rememberMe,
    LoginStatus? status,
    AuthFailure? failure,
    bool? showErrors,
    bool clearFailure = false,
  }) {
    return LoginState(
      email: email ?? this.email,
      password: password ?? this.password,
      rememberMe: rememberMe ?? this.rememberMe,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      showErrors: showErrors ?? this.showErrors,
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

  Future<void> submit() async {
    state = state.copyWith(showErrors: true, clearFailure: true);
    if (!state.isValid) return;

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
    );
    result.match(
      (failure) => state = state.copyWith(
        status: LoginStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(status: LoginStatus.success),
    );
  }

  void reset() => state = const LoginState();
}

final loginNotifierProvider =
    NotifierProvider<LoginNotifier, LoginState>(LoginNotifier.new);
