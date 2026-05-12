import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/validation/email.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum PasswordResetRequestStatus { initial, submitting, success, failure }

/// Estado del formulario "olvidé mi contraseña" (envío del email).
class PasswordResetRequestState {
  const PasswordResetRequestState({
    this.email = const Email.pure(),
    this.status = PasswordResetRequestStatus.initial,
    this.failure,
    this.sentToEmail,
    this.showErrors = false,
  });

  final Email email;
  final PasswordResetRequestStatus status;
  final AuthFailure? failure;
  final String? sentToEmail;
  final bool showErrors;

  bool get isValid => Formz.validate([email]);
  bool get isSubmitting => status == PasswordResetRequestStatus.submitting;

  PasswordResetRequestState copyWith({
    Email? email,
    PasswordResetRequestStatus? status,
    AuthFailure? failure,
    String? sentToEmail,
    bool? showErrors,
    bool clearFailure = false,
  }) {
    return PasswordResetRequestState(
      email: email ?? this.email,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      sentToEmail: sentToEmail ?? this.sentToEmail,
      showErrors: showErrors ?? this.showErrors,
    );
  }
}

class PasswordResetRequestNotifier
    extends Notifier<PasswordResetRequestState> {
  @override
  PasswordResetRequestState build() => const PasswordResetRequestState();

  void emailChanged(String v) {
    state = state.copyWith(
      email: Email.dirty(v.trim()),
      clearFailure: true,
    );
  }

  Future<void> submit() async {
    state = state.copyWith(showErrors: true, clearFailure: true);
    if (!state.isValid) return;

    state = state.copyWith(status: PasswordResetRequestStatus.submitting);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.sendPasswordReset(state.email.value.trim());
    result.match(
      (failure) => state = state.copyWith(
        status: PasswordResetRequestStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(
        status: PasswordResetRequestStatus.success,
        sentToEmail: state.email.value.trim(),
      ),
    );
  }

  void reset() => state = const PasswordResetRequestState();
}

final passwordResetRequestNotifierProvider = NotifierProvider<
    PasswordResetRequestNotifier,
    PasswordResetRequestState>(PasswordResetRequestNotifier.new);
