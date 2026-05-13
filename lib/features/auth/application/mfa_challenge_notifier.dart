import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum MfaChallengeStatus { loading, ready, verifying, success, failure }

/// Estado para el desafío MFA durante el login: después de password
/// correcto pero antes de poder entrar a /home, el usuario tiene que
/// introducir el código TOTP de su app autenticadora.
class MfaChallengeState {
  const MfaChallengeState({
    this.status = MfaChallengeStatus.loading,
    this.factor,
    this.code = '',
    this.failure,
  });

  final MfaChallengeStatus status;
  final MfaFactor? factor;
  final String code;
  final AuthFailure? failure;

  static const int codeLength = 6;

  bool get isValid => code.length == codeLength;
  bool get isVerifying => status == MfaChallengeStatus.verifying;

  MfaChallengeState copyWith({
    MfaChallengeStatus? status,
    MfaFactor? factor,
    String? code,
    AuthFailure? failure,
    bool clearFailure = false,
  }) {
    return MfaChallengeState(
      status: status ?? this.status,
      factor: factor ?? this.factor,
      code: code ?? this.code,
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

  Future<void> verify() async {
    if (!state.isValid || state.factor == null) return;
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
}

final mfaChallengeNotifierProvider =
    NotifierProvider<MfaChallengeNotifier, MfaChallengeState>(
  MfaChallengeNotifier.new,
);
