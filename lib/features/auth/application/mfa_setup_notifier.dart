import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum MfaSetupStep { idle, qrCode, verifying, done, failure }

class MfaSetupState {
  const MfaSetupState({
    this.step = MfaSetupStep.idle,
    this.enrollment,
    this.code = '',
    this.failure,
  });

  final MfaSetupStep step;
  final MfaTotpEnrollment? enrollment;
  final String code;
  final AuthFailure? failure;

  static const int codeLength = 6;

  bool get isWorking =>
      step == MfaSetupStep.verifying || step == MfaSetupStep.idle && false;

  bool get canSubmit =>
      step == MfaSetupStep.qrCode &&
      code.length == codeLength &&
      enrollment != null;

  MfaSetupState copyWith({
    MfaSetupStep? step,
    MfaTotpEnrollment? enrollment,
    String? code,
    AuthFailure? failure,
    bool clearFailure = false,
  }) {
    return MfaSetupState(
      step: step ?? this.step,
      enrollment: enrollment ?? this.enrollment,
      code: code ?? this.code,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class MfaSetupNotifier extends Notifier<MfaSetupState> {
  @override
  MfaSetupState build() => const MfaSetupState();

  /// Inicia el enrollment: llama a Supabase, recibe el QR y guarda
  /// el factorId. Pasa al step `qrCode`.
  Future<void> startEnrollment({String? friendlyName}) async {
    state = state.copyWith(
      step: MfaSetupStep.idle,
      clearFailure: true,
    );
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.enrollTotp(friendlyName: friendlyName);
    result.match(
      (failure) => state = state.copyWith(
        step: MfaSetupStep.failure,
        failure: failure,
      ),
      (enrollment) => state = state.copyWith(
        step: MfaSetupStep.qrCode,
        enrollment: enrollment,
      ),
    );
  }

  void codeChanged(String v) {
    state = state.copyWith(code: v, clearFailure: true);
  }

  /// Verifica el código del autenticador. Si OK → done.
  Future<void> verify() async {
    if (!state.canSubmit) return;
    state = state.copyWith(step: MfaSetupStep.verifying, clearFailure: true);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.verifyMfaEnrollment(
      factorId: state.enrollment!.factorId,
      code: state.code,
    );
    result.match(
      (failure) => state = state.copyWith(
        step: MfaSetupStep.qrCode,
        failure: failure,
      ),
      (_) => state = state.copyWith(step: MfaSetupStep.done),
    );
  }

  void reset() => state = const MfaSetupState();
}

final mfaSetupNotifierProvider =
    NotifierProvider<MfaSetupNotifier, MfaSetupState>(MfaSetupNotifier.new);
