import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/validation/email.dart';
import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/features/audit/domain/audit_events.dart';
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

  /// Marca el form como "ya validado" (muestra errores si los hay) y
  /// devuelve si los campos pasan validacion. Util para que la UI
  /// pueda decidir si abrir el dialog de re-auth antes de invocar la
  /// API, sin disparar `submit()` y arriesgarse a actualizar el email
  /// sin pasar por el gate.
  bool validateForm() {
    state = state.copyWith(showErrors: true, clearFailure: true);
    return state.isValid;
  }

  /// Invoca la API de Supabase Auth para cambiar el email del user.
  /// **NO valida** ni abre dialogos -- se asume que el caller ya ha
  /// llamado a `validateForm()` y `ReauthDialog.show(...)` antes y han
  /// devuelto true. Si llamas a esta funcion sin pasar por esos dos
  /// pasos, el cambio se hace sin gate de re-auth (estaria mal por
  /// seguridad).
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
      (_) {
        state = state.copyWith(
          status: ChangeEmailStatus.success,
          sentToEmail: state.newEmail.value.trim(),
        );
        ref.read(auditLoggerProvider).log(AuditEvents.emailChangeRequested);
      },
    );
  }

  void reset() => state = const ChangeEmailState();
}

final changeEmailNotifierProvider =
    NotifierProvider<ChangeEmailNotifier, ChangeEmailState>(
  ChangeEmailNotifier.new,
);
