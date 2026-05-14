import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/mfa_providers.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

/// Máquina de estados de la pantalla `/mfa-setup`:
///
///   loading ─┬─► alreadyEnabled ──(disable)──► unenrolling ──► disabled
///            └─► qrCode ──(verify)──► verifying ──► done
///                  ▲                     │
///                  └──── failure ◄───────┘
enum MfaSetupStep {
  loading,
  alreadyEnabled,
  qrCode,
  verifying,
  done,
  unenrolling,
  disabled,
  failure,
}

class MfaSetupState {
  const MfaSetupState({
    this.step = MfaSetupStep.loading,
    this.enrollment,
    this.existingFactorId,
    this.code = '',
    this.failure,
  });

  final MfaSetupStep step;
  final MfaTotpEnrollment? enrollment;

  /// Si el usuario ya tiene un factor TOTP verificado, su id (para poder
  /// desenrolarlo).
  final String? existingFactorId;

  final String code;
  final AuthFailure? failure;

  static const int codeLength = 6;

  bool get canSubmit =>
      step == MfaSetupStep.qrCode &&
      code.length == codeLength &&
      enrollment != null;

  MfaSetupState copyWith({
    MfaSetupStep? step,
    MfaTotpEnrollment? enrollment,
    String? existingFactorId,
    String? code,
    AuthFailure? failure,
    bool clearFailure = false,
  }) {
    return MfaSetupState(
      step: step ?? this.step,
      enrollment: enrollment ?? this.enrollment,
      existingFactorId: existingFactorId ?? this.existingFactorId,
      code: code ?? this.code,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class MfaSetupNotifier extends Notifier<MfaSetupState> {
  @override
  MfaSetupState build() {
    _init();
    return const MfaSetupState();
  }

  /// Al entrar a la pantalla: comprueba si ya hay un factor TOTP verificado.
  /// - Sí → step `alreadyEnabled` (el usuario puede desactivarlo).
  /// - No → arranca el enrollment automáticamente.
  Future<void> _init() async {
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.listMfaFactors();
    final verified = result.fold(
      (_) => <MfaFactor>[],
      (factors) =>
          factors.where((f) => f.isVerified && f.type == 'totp').toList(),
    );
    if (verified.isNotEmpty) {
      state = state.copyWith(
        step: MfaSetupStep.alreadyEnabled,
        existingFactorId: verified.first.id,
      );
    } else {
      await _startEnrollment();
    }
  }

  Future<void> _startEnrollment() async {
    state = state.copyWith(step: MfaSetupStep.loading, clearFailure: true);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.enrollTotp(friendlyName: 'myapp');
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

  /// Reintenta el enrollment tras un fallo de red, etc.
  Future<void> retryEnrollment() => _startEnrollment();

  void codeChanged(String v) {
    state = state.copyWith(code: v, clearFailure: true);
  }

  /// Verifica el código del autenticador para completar el enrollment.
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
      (_) {
        state = state.copyWith(step: MfaSetupStep.done);
        ref.invalidate(mfaFactorsProvider);
      },
    );
  }

  /// Desactiva (unenroll) el factor TOTP verificado existente.
  Future<void> disable() async {
    final factorId = state.existingFactorId;
    if (factorId == null) return;
    state = state.copyWith(
      step: MfaSetupStep.unenrolling,
      clearFailure: true,
    );
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.unenrollMfa(factorId);
    result.match(
      (failure) => state = state.copyWith(
        step: MfaSetupStep.alreadyEnabled,
        failure: failure,
      ),
      (_) {
        state = state.copyWith(step: MfaSetupStep.disabled);
        ref.invalidate(mfaFactorsProvider);
      },
    );
  }

  void reset() => state = const MfaSetupState();
}

final mfaSetupNotifierProvider =
    NotifierProvider<MfaSetupNotifier, MfaSetupState>(MfaSetupNotifier.new);
