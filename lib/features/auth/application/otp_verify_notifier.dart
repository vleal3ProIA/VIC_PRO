import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum OtpVerifyStatus { initial, submitting, success, failure }

/// Estado del formulario "verificar código OTP".
class OtpVerifyState {
  const OtpVerifyState({
    required this.email,
    this.code = '',
    this.status = OtpVerifyStatus.initial,
    this.failure,
  });

  final String email;
  final String code;
  final OtpVerifyStatus status;
  final AuthFailure? failure;

  static const int codeLength = 6;

  bool get isValid => code.length == codeLength;
  bool get isSubmitting => status == OtpVerifyStatus.submitting;

  OtpVerifyState copyWith({
    String? code,
    OtpVerifyStatus? status,
    AuthFailure? failure,
    bool clearFailure = false,
  }) {
    return OtpVerifyState(
      email: email,
      code: code ?? this.code,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class OtpVerifyNotifier extends FamilyNotifier<OtpVerifyState, String> {
  @override
  OtpVerifyState build(String email) => OtpVerifyState(email: email);

  void codeChanged(String v) {
    state = state.copyWith(code: v, clearFailure: true);
  }

  Future<void> submit() async {
    if (!state.isValid) return;
    state = state.copyWith(status: OtpVerifyStatus.submitting);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.verifyEmailOtp(
      email: state.email,
      token: state.code,
    );
    result.match(
      (failure) => state = state.copyWith(
        status: OtpVerifyStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(status: OtpVerifyStatus.success),
    );
  }
}

final otpVerifyNotifierProvider =
    NotifierProvider.family<OtpVerifyNotifier, OtpVerifyState, String>(
  OtpVerifyNotifier.new,
);
