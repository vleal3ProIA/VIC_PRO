import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/security/leaked_password_checker.dart';
import 'package:myapp/core/validation/password.dart';
import 'package:myapp/core/validation/password_confirmation.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum PasswordUpdateStatus { initial, submitting, success, failure }

/// Estado del formulario "elige una contraseña nueva" tras llegar por
/// el callback de recovery.
class PasswordUpdateState {
  const PasswordUpdateState({
    this.password = const Password.pure(),
    this.confirmation = const PasswordConfirmation.pure(),
    this.status = PasswordUpdateStatus.initial,
    this.failure,
    this.showErrors = false,
  });

  final Password password;
  final PasswordConfirmation confirmation;
  final PasswordUpdateStatus status;
  final AuthFailure? failure;
  final bool showErrors;

  bool get isValid => Formz.validate([password, confirmation]);
  bool get isSubmitting => status == PasswordUpdateStatus.submitting;

  PasswordUpdateState copyWith({
    Password? password,
    PasswordConfirmation? confirmation,
    PasswordUpdateStatus? status,
    AuthFailure? failure,
    bool? showErrors,
    bool clearFailure = false,
  }) {
    return PasswordUpdateState(
      password: password ?? this.password,
      confirmation: confirmation ?? this.confirmation,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      showErrors: showErrors ?? this.showErrors,
    );
  }
}

class PasswordUpdateNotifier extends Notifier<PasswordUpdateState> {
  @override
  PasswordUpdateState build() => const PasswordUpdateState();

  void passwordChanged(String v) {
    state = state.copyWith(
      password: Password.dirty(v),
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
        password: state.password.value,
        value: v,
      ),
      clearFailure: true,
    );
  }

  Future<void> submit() async {
    state = state.copyWith(showErrors: true, clearFailure: true);
    if (!state.isValid) return;

    state = state.copyWith(status: PasswordUpdateStatus.submitting);

    // Leaked password protection (HaveIBeenPwned). Fail-open si HIBP
    // no responde — no bloqueamos el reset por una caída del tercero.
    final leaked = await ref
        .read(leakedPasswordCheckerProvider)
        .isLeaked(state.password.value);
    if (leaked) {
      state = state.copyWith(
        status: PasswordUpdateStatus.failure,
        failure: const AuthLeakedPassword(),
      );
      return;
    }

    final repo = ref.read(authRepositoryProvider);
    final result = await repo.updatePassword(state.password.value);
    result.match(
      (failure) => state = state.copyWith(
        status: PasswordUpdateStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(status: PasswordUpdateStatus.success),
    );
  }

  void reset() => state = const PasswordUpdateState();
}

final passwordUpdateNotifierProvider =
    NotifierProvider<PasswordUpdateNotifier, PasswordUpdateState>(
  PasswordUpdateNotifier.new,
);
