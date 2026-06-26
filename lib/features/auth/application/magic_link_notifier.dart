import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';

import 'package:myapp/core/config/env_config.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum MagicLinkStatus { initial, submitting, success, failure }

/// Estado del formulario de Magic Link (passwordless email).
class MagicLinkState {
  const MagicLinkState({
    this.email = const Email.pure(),
    this.status = MagicLinkStatus.initial,
    this.failure,
    this.sentToEmail,
    this.showErrors = false,
    this.captchaToken,
  });

  final Email email;
  final MagicLinkStatus status;
  final AuthFailure? failure;
  final String? sentToEmail;
  final bool showErrors;

  /// Token de Cloudflare Turnstile. Supabase Auth aplica Bot protection a
  /// `/otp` (magic link + OTP), no solo a signup, así que necesitamos
  /// pasarlo al backend para evitar `captcha_failed`.
  final String? captchaToken;

  bool get isSubmitting => status == MagicLinkStatus.submitting;

  bool get isCaptchaRequired =>
      kIsWeb && EnvConfig.turnstileSitekey.isNotEmpty;

  bool get hasCaptchaToken => captchaToken != null && captchaToken!.isNotEmpty;

  bool get isValid =>
      Formz.validate([email]) && (!isCaptchaRequired || hasCaptchaToken);

  MagicLinkState copyWith({
    Email? email,
    MagicLinkStatus? status,
    AuthFailure? failure,
    String? sentToEmail,
    bool? showErrors,
    String? captchaToken,
    bool clearFailure = false,
    bool clearCaptchaToken = false,
  }) {
    return MagicLinkState(
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

class MagicLinkNotifier extends Notifier<MagicLinkState> {
  @override
  MagicLinkState build() => const MagicLinkState();

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

    state = state.copyWith(status: MagicLinkStatus.submitting);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.signInWithMagicLink(
      state.email.value.trim(),
      captchaToken: state.captchaToken,
    );
    result.match(
      (failure) => state = state.copyWith(
        status: MagicLinkStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(
        status: MagicLinkStatus.success,
        sentToEmail: state.email.value.trim(),
      ),
    );
  }

  void reset() => state = const MagicLinkState();
}

final magicLinkNotifierProvider =
    NotifierProvider<MagicLinkNotifier, MagicLinkState>(MagicLinkNotifier.new);
