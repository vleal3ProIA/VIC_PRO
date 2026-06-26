import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/config/env_config.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum OtpRequestStatus { initial, submitting, success, failure }

/// Estado del formulario "pedir código OTP".
class OtpRequestState {
  const OtpRequestState({
    this.email = const Email.pure(),
    this.status = OtpRequestStatus.initial,
    this.failure,
    this.sentToEmail,
    this.showErrors = false,
    this.captchaToken,
  });

  final Email email;
  final OtpRequestStatus status;
  final AuthFailure? failure;
  final String? sentToEmail;
  final bool showErrors;

  /// Token de Cloudflare Turnstile. `/otp` (mismo endpoint que magic link)
  /// está protegido por Bot protection en Supabase Auth.
  final String? captchaToken;

  bool get isSubmitting => status == OtpRequestStatus.submitting;

  bool get isCaptchaRequired =>
      kIsWeb && EnvConfig.turnstileSitekey.isNotEmpty;

  bool get hasCaptchaToken => captchaToken != null && captchaToken!.isNotEmpty;

  bool get isValid =>
      Formz.validate([email]) && (!isCaptchaRequired || hasCaptchaToken);

  OtpRequestState copyWith({
    Email? email,
    OtpRequestStatus? status,
    AuthFailure? failure,
    String? sentToEmail,
    bool? showErrors,
    String? captchaToken,
    bool clearFailure = false,
    bool clearCaptchaToken = false,
  }) {
    return OtpRequestState(
      email: email ?? this.email,
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      sentToEmail: sentToEmail ?? this.sentToEmail,
      showErrors: showErrors ?? this.showErrors,
      captchaToken:
          clearCaptchaToken ? null : (captchaToken ?? this.captchaToken),
    );
  }
}

class OtpRequestNotifier extends Notifier<OtpRequestState> {
  @override
  OtpRequestState build() => const OtpRequestState();

  void emailChanged(String v) {
    state = state.copyWith(
      email: Email.dirty(v.trim()),
      clearFailure: true,
    );
  }

  void captchaTokenChanged(String token) {
    state = state.copyWith(captchaToken: token, clearFailure: true);
  }

  void captchaTokenCleared() {
    state = state.copyWith(clearCaptchaToken: true);
  }

  Future<void> submit() async {
    state = state.copyWith(showErrors: true, clearFailure: true);
    if (!state.isValid) return;

    state = state.copyWith(status: OtpRequestStatus.submitting);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.requestEmailOtp(
      state.email.value.trim(),
      captchaToken: state.captchaToken,
    );
    result.match(
      (failure) => state = state.copyWith(
        status: OtpRequestStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(
        status: OtpRequestStatus.success,
        sentToEmail: state.email.value.trim(),
      ),
    );
  }

  void reset() => state = const OtpRequestState();
}

final otpRequestNotifierProvider =
    NotifierProvider<OtpRequestNotifier, OtpRequestState>(
  OtpRequestNotifier.new,
);
