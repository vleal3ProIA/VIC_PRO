import 'package:flutter/widgets.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/core/validation/password.dart';
import 'package:myapp/core/validation/password_confirmation.dart';
import 'package:myapp/core/validation/username.dart';

/// Resuelve enums de validación a strings localizados.
/// Mantiene los validators puros (sin dependencia de Flutter / l10n).
class ValidationMessages {
  const ValidationMessages._();

  static String? username(BuildContext c, UsernameValidationError? e) {
    if (e == null) return null;
    final l = c.l10n;
    return switch (e) {
      UsernameValidationError.empty => l.errorRequired,
      UsernameValidationError.tooShort => l.errorUsernameTooShort(Username.minLength),
      UsernameValidationError.tooLong => l.errorUsernameTooLong(Username.maxLength),
      UsernameValidationError.invalidChars => l.errorUsernameInvalidChars,
    };
  }

  static String? email(BuildContext c, EmailValidationError? e) {
    if (e == null) return null;
    final l = c.l10n;
    return switch (e) {
      EmailValidationError.empty => l.errorRequired,
      EmailValidationError.invalid => l.errorEmailInvalid,
      EmailValidationError.tooLong => l.errorEmailTooLong,
    };
  }

  static String? password(BuildContext c, PasswordValidationError? e) {
    if (e == null) return null;
    final l = c.l10n;
    return switch (e) {
      PasswordValidationError.empty => l.errorRequired,
      PasswordValidationError.tooShort => l.errorPasswordTooShort,
      PasswordValidationError.missingLowercase => l.errorPasswordMissingLower,
      PasswordValidationError.missingUppercase => l.errorPasswordMissingUpper,
      PasswordValidationError.missingDigit => l.errorPasswordMissingDigit,
      PasswordValidationError.missingSpecial => l.errorPasswordMissingSpecial,
    };
  }

  static String? passwordConfirmation(
    BuildContext c,
    PasswordConfirmationValidationError? e,
  ) {
    if (e == null) return null;
    final l = c.l10n;
    return switch (e) {
      PasswordConfirmationValidationError.empty => l.errorRequired,
      PasswordConfirmationValidationError.mismatch => l.errorPasswordMismatch,
    };
  }
}
