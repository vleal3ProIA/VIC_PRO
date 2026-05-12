import 'package:formz/formz.dart';

import 'package:myapp/core/constants/app_constants.dart';

enum PasswordValidationError {
  empty,
  tooShort,
  missingLowercase,
  missingUppercase,
  missingDigit,
  missingSpecial,
}

/// Reglas enterprise:
/// - Mínimo [AppConstants.passwordMinLength] (8) caracteres.
/// - Al menos: 1 minúscula, 1 mayúscula, 1 dígito, 1 carácter especial.
class Password extends FormzInput<String, PasswordValidationError> {
  const Password.pure() : super.pure('');
  const Password.dirty([super.value = '']) : super.dirty();

  static final RegExp _lower = RegExp('[a-z]');
  static final RegExp _upper = RegExp('[A-Z]');
  static final RegExp _digit = RegExp('[0-9]');
  static final RegExp _special = RegExp(r'[!@#\$%\^&\*\(\)_\+\-=\[\]\{\};:"\\|,.<>\/?~`]');

  @override
  PasswordValidationError? validator(String value) {
    if (value.isEmpty) return PasswordValidationError.empty;
    if (value.length < AppConstants.passwordMinLength) {
      return PasswordValidationError.tooShort;
    }
    if (!_lower.hasMatch(value)) return PasswordValidationError.missingLowercase;
    if (!_upper.hasMatch(value)) return PasswordValidationError.missingUppercase;
    if (!_digit.hasMatch(value)) return PasswordValidationError.missingDigit;
    if (!_special.hasMatch(value)) return PasswordValidationError.missingSpecial;
    return null;
  }

  /// Fuerza visible para UI (0..4). 4 = cumple todas las reglas.
  static int strength(String value) {
    if (value.isEmpty) return 0;
    var score = 0;
    if (value.length >= AppConstants.passwordMinLength) score++;
    if (_lower.hasMatch(value) && _upper.hasMatch(value)) score++;
    if (_digit.hasMatch(value)) score++;
    if (_special.hasMatch(value)) score++;
    return score;
  }
}
