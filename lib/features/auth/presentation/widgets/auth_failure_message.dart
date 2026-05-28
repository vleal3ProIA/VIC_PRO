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
    AuthLeakedPassword() => l.authErrorLeakedPassword,
    AuthEmailNotConfirmed() => l.authErrorEmailNotConfirmed,
    AuthEmailNotRegistered() => l.authErrorEmailNotRegistered,
    AuthInvalidCredentials() => l.authErrorInvalidCredentials,
    AuthOtpInvalid() => l.authErrorOtpInvalid,
    AuthMfaInvalid() => l.authErrorMfaInvalid,
    AuthRateLimited() => l.authErrorRateLimited,
    AuthNetworkError() => l.authErrorNetwork,
    AuthPasskeyFailed() => l.passkeyActionFailure,
    AuthUnknown() => l.authErrorUnknown,
  };
}

/// Detalle técnico crudo (code + mensaje de GoTrue) cuando el fallo es opaco
/// (`AuthUnknown`). Se muestra como texto secundario en pantallas como el
/// setup de MFA para diagnosticar "Algo salió mal" sin tener que mirar logs:
/// revela, por ejemplo, si TOTP está deshabilitado en el proyecto o si se
/// alcanzó el límite de factores. `null` cuando no aporta nada.
String? authFailureTechnicalDetail(AuthFailure failure) =>
    failure is AuthUnknown ? failure.message : null;
