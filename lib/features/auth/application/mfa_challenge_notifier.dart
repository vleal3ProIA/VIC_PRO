import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum MfaChallengeStatus { loading, ready, verifying, success, failure }

/// Estado para el desafío MFA durante el login: después de password
/// correcto pero antes de poder entrar a /home, el usuario tiene que
/// introducir el código TOTP de su app autenticadora — o, si la perdió, un
/// código de recuperación.
class MfaChallengeState {
  const MfaChallengeState({
    this.status = MfaChallengeStatus.loading,
    this.factor,
    this.code = '',
    this.useRecoveryCode = false,
    this.recoveryCode = '',
    this.failure,
  });

  final MfaChallengeStatus status;
  final MfaFactor? factor;
  final String code;

  /// Si `true`, el usuario está introduciendo un código de recuperación en
  /// lugar del TOTP.
  final bool useRecoveryCode;
  final String recoveryCode;

  final AuthFailure? failure;

  static const int codeLength = 6;

  bool get isTotpValid => code.length == codeLength;
  bool get isRecoveryValid => recoveryCode.trim().isNotEmpty;
  bool get isValid => useRecoveryCode ? isRecoveryValid : isTotpValid;
  bool get isVerifying => status == MfaChallengeStatus.verifying;

  MfaChallengeState copyWith({
    MfaChallengeStatus? status,
    MfaFactor? factor,
    String? code,
    bool? useRecoveryCode,
    String? recoveryCode,
    AuthFailure? failure,
    bool clearFailure = false,
  }) {
    return MfaChallengeState(
      status: status ?? this.status,
      factor: factor ?? this.factor,
      code: code ?? this.code,
      useRecoveryCode: useRecoveryCode ?? this.useRecoveryCode,
      recoveryCode: recoveryCode ?? this.recoveryCode,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class MfaChallengeNotifier extends Notifier<MfaChallengeState> {
  @override
  MfaChallengeState build() {
    // Cargar el primer factor verificado al construir.
    Future.microtask(_loadFactor);
    return const MfaChallengeState();
  }

  Future<void> _loadFactor() async {
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.listMfaFactors();
    result.match(
      (failure) => state = state.copyWith(
        status: MfaChallengeStatus.failure,
        failure: failure,
      ),
      (factors) {
        final totp = factors.where((f) => f.isVerified && f.type == 'totp');
        if (totp.isEmpty) {
          state = state.copyWith(
            status: MfaChallengeStatus.failure,
            failure: const AuthUnknown(
              message: 'No verified TOTP factor found.',
            ),
          );
          return;
        }
        state = state.copyWith(
          status: MfaChallengeStatus.ready,
          factor: totp.first,
        );
      },
    );
  }

  void codeChanged(String v) {
    state = state.copyWith(code: v, clearFailure: true);
  }

  void recoveryCodeChanged(String v) {
    state = state.copyWith(recoveryCode: v, clearFailure: true);
  }

  /// Alterna entre el modo TOTP y el de código de recuperación.
  void toggleRecoveryMode() {
    state = state.copyWith(
      useRecoveryCode: !state.useRecoveryCode,
      code: '',
      recoveryCode: '',
      clearFailure: true,
    );
  }

  Future<void> verify() async {
    if (state.useRecoveryCode) {
      await _verifyRecoveryCode();
      return;
    }
    if (!state.isTotpValid || state.factor == null || state.isVerifying) {
      return;
    }
    state = state.copyWith(status: MfaChallengeStatus.verifying);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.challengeAndVerifyMfa(
      factorId: state.factor!.id,
      code: state.code,
    );
    result.match(
      (failure) => state = state.copyWith(
        status: MfaChallengeStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(status: MfaChallengeStatus.success),
    );
  }

  /// Verifica un código de recuperación. Si es válido, la Edge Function
  /// elimina el factor MFA y refresca la sesión: el guard del router, que
  /// observa el estado de auth, redirige a /home.
  Future<void> _verifyRecoveryCode() async {
    if (!state.isRecoveryValid || state.isVerifying) return;
    state = state.copyWith(status: MfaChallengeStatus.verifying);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.verifyRecoveryCode(state.recoveryCode.trim());
    result.match(
      (failure) => state = state.copyWith(
        status: MfaChallengeStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(status: MfaChallengeStatus.success),
    );
  }
}

final mfaChallengeNotifierProvider =
    NotifierProvider<MfaChallengeNotifier, MfaChallengeState>(
  MfaChallengeNotifier.new,
);
