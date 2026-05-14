import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum AccountDeletionStatus { initial, submitting, success, failure }

/// Estado de la pantalla de borrado de cuenta.
///
/// Requiere dos confirmaciones para evitar borrados accidentales:
/// la contraseña actual (reautenticación) y una casilla explícita de que se
/// entiende que la acción es permanente.
class AccountDeletionState {
  const AccountDeletionState({
    this.password = '',
    this.acknowledged = false,
    this.status = AccountDeletionStatus.initial,
    this.failure,
    this.showErrors = false,
  });

  final String password;
  final bool acknowledged;
  final AccountDeletionStatus status;
  final AuthFailure? failure;
  final bool showErrors;

  bool get passwordIsEmpty => password.isEmpty;
  bool get isValid => password.isNotEmpty && acknowledged;
  bool get isSubmitting => status == AccountDeletionStatus.submitting;

  AccountDeletionState copyWith({
    String? password,
    bool? acknowledged,
    AccountDeletionStatus? status,
    AuthFailure? failure,
    bool? showErrors,
    bool clearFailure = false,
  }) {
    return AccountDeletionState(
      password: password ?? this.password,
      acknowledged: acknowledged ?? this.acknowledged,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      showErrors: showErrors ?? this.showErrors,
    );
  }
}

class AccountDeletionNotifier extends Notifier<AccountDeletionState> {
  @override
  AccountDeletionState build() => const AccountDeletionState();

  void passwordChanged(String v) {
    state = state.copyWith(password: v, clearFailure: true);
  }

  void acknowledgedChanged({required bool value}) {
    state = state.copyWith(acknowledged: value, clearFailure: true);
  }

  /// Borra la cuenta. Solo procede si hay contraseña y la casilla marcada;
  /// la pantalla además muestra un diálogo de confirmación antes de llamar.
  Future<void> submit() async {
    state = state.copyWith(showErrors: true, clearFailure: true);
    if (!state.isValid || state.isSubmitting) return;

    state = state.copyWith(status: AccountDeletionStatus.submitting);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.deleteAccount(password: state.password);
    result.match(
      (failure) => state = state.copyWith(
        status: AccountDeletionStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(status: AccountDeletionStatus.success),
    );
  }

  void reset() => state = const AccountDeletionState();
}

final accountDeletionNotifierProvider =
    NotifierProvider<AccountDeletionNotifier, AccountDeletionState>(
  AccountDeletionNotifier.new,
);
