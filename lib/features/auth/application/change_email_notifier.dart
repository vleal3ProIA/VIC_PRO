import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/validation/email.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum ChangeEmailStatus { initial, submitting, success, failure }

class ChangeEmailState {
  const ChangeEmailState({
    this.newEmail = const Email.pure(),
    this.status = ChangeEmailStatus.initial,
    this.failure,
    this.sentToEmail,
    this.showErrors = false,
  });

  final Email newEmail;
  final ChangeEmailStatus status;
  final AuthFailure? failure;
  final String? sentToEmail;
  final bool showErrors;

  bool get isValid => Formz.validate([newEmail]);
  bool get isSubmitting => status == ChangeEmailStatus.submitting;

  ChangeEmailState copyWith({
    Email? newEmail,
    ChangeEmailStatus? status,
    AuthFailure? failure,
    String? sentToEmail,
    bool? showErrors,
    bool clearFailure = false,
  }) {
    return ChangeEmailState(
      newEmail: newEmail ?? this.newEmail,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      sentToEmail: sentToEmail ?? this.sentToEmail,
      showErrors: showErrors ?? this.showErrors,
    );
  }
}

class ChangeEmailNotifier extends Notifier<ChangeEmailState> {
  @override
  ChangeEmailState build() => const ChangeEmailState();

  void emailChanged(String v) {
    state = state.copyWith(
      newEmail: Email.dirty(v.trim()),
      clearFailure: true,
    );
  }

  Future<void> submit() async {
    state = state.copyWith(showErrors: true, clearFailure: true);
    if (!state.isValid) return;

    state = state.copyWith(status: ChangeEmailStatus.submitting);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.changeEmail(state.newEmail.value.trim());
    result.match(
      (failure) => state = state.copyWith(
        status: ChangeEmailStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(
        status: ChangeEmailStatus.success,
        sentToEmail: state.newEmail.value.trim(),
      ),
    );
  }

  void reset() => state = const ChangeEmailState();
}

final changeEmailNotifierProvider =
    NotifierProvider<ChangeEmailNotifier, ChangeEmailState>(
  ChangeEmailNotifier.new,
);
