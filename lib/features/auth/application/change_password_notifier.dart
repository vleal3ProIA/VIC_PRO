import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/validation/password.dart';
import 'package:myapp/core/validation/password_confirmation.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum ChangePasswordStatus { initial, submitting, success, failure }

enum CurrentPasswordError { empty }

/// Input simple para la contraseña actual: solo "no vacía". La validación
/// real (¿es correcta?) la hace el backend al reautenticar.
class CurrentPasswordInput extends FormzInput<String, CurrentPasswordError> {
  const CurrentPasswordInput.pure() : super.pure('');
  const CurrentPasswordInput.dirty([super.value = '']) : super.dirty();

  @override
  CurrentPasswordError? validator(String value) {
    if (value.isEmpty) return CurrentPasswordError.empty;
    return null;
  }
}

class ChangePasswordState {
  const ChangePasswordState({
    this.currentPassword = const CurrentPasswordInput.pure(),
    this.newPassword = const Password.pure(),
    this.confirmation = const PasswordConfirmation.pure(),
    this.status = ChangePasswordStatus.initial,
    this.failure,
    this.showErrors = false,
  });

  final CurrentPasswordInput currentPassword;
  final Password newPassword;
  final PasswordConfirmation confirmation;
  final ChangePasswordStatus status;
  final AuthFailure? failure;
  final bool showErrors;

  bool get isValid =>
      Formz.validate([currentPassword, newPassword, confirmation]);
  bool get isSubmitting => status == ChangePasswordStatus.submitting;
  bool get currentIsEmpty => currentPassword.value.isEmpty;

  ChangePasswordState copyWith({
    CurrentPasswordInput? currentPassword,
    Password? newPassword,
    PasswordConfirmation? confirmation,
    ChangePasswordStatus? status,
    AuthFailure? failure,
    bool? showErrors,
    bool clearFailure = false,
  }) {
    return ChangePasswordState(
      currentPassword: currentPassword ?? this.currentPassword,
      newPassword: newPassword ?? this.newPassword,
      confirmation: confirmation ?? this.confirmation,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      showErrors: showErrors ?? this.showErrors,
    );
  }
}

class ChangePasswordNotifier extends Notifier<ChangePasswordState> {
  @override
  ChangePasswordState build() => const ChangePasswordState();

  void currentPasswordChanged(String v) {
    state = state.copyWith(
      currentPassword: CurrentPasswordInput.dirty(v),
      clearFailure: true,
    );
  }

  void newPasswordChanged(String v) {
    state = state.copyWith(
      newPassword: Password.dirty(v),
      confirmation: PasswordConfirmation.dirty(
        password: v,
        value: state.confirmation.value,
      ),
      clearFailure: true,
    );
  }

  void confirmationChanged(String v) {
    state = state.copyWith(
      confirmation: PasswordConfirmation.dirty(
        password: state.newPassword.value,
        value: v,
      ),
      clearFailure: true,
    );
  }

  Future<void> submit() async {
    state = state.copyWith(showErrors: true, clearFailure: true);
    if (!state.isValid) return;

    state = state.copyWith(status: ChangePasswordStatus.submitting);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.changePassword(
      currentPassword: state.currentPassword.value,
      newPassword: state.newPassword.value,
    );
    result.match(
      (failure) => state = state.copyWith(
        status: ChangePasswordStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(status: ChangePasswordStatus.success),
    );
  }

  void reset() => state = const ChangePasswordState();
}

final changePasswordNotifierProvider =
    NotifierProvider<ChangePasswordNotifier, ChangePasswordState>(
  ChangePasswordNotifier.new,
);
