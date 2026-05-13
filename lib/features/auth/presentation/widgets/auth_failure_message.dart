import 'package:flutter/widgets.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

/// Traduce un [AuthFailure] al mensaje localizado mostrado en el slot de
/// errores generales.
String authFailureMessage(BuildContext context, AuthFailure failure) {
  final l = context.l10n;
  return switch (failure) {
    AuthUserAlreadyExists() => l.authErrorUserExists,
    AuthWeakPassword() => l.authErrorWeakPassword,
    AuthEmailNotConfirmed() => l.authErrorEmailNotConfirmed,
    AuthInvalidCredentials() => l.authErrorInvalidCredentials,
    AuthOtpInvalid() => l.authErrorOtpInvalid,
    AuthRateLimited() => l.authErrorRateLimited,
    AuthNetworkError() => l.authErrorNetwork,
    AuthUnknown() => l.authErrorUnknown,
  };
}
