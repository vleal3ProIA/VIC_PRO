import 'package:formz/formz.dart';

enum EmailValidationError { empty, invalid, tooLong }

/// Validación RFC-pragmática (no full RFC 5322, pero atrapa el 99%).
/// Longitud máxima razonable: 254.
class Email extends FormzInput<String, EmailValidationError> {
  const Email.pure() : super.pure('');
  const Email.dirty([super.value = '']) : super.dirty();

  static const int maxLength = 254;

  static final RegExp _regex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    '[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  @override
  EmailValidationError? validator(String value) {
    final v = value.trim();
    if (v.isEmpty) return EmailValidationError.empty;
    if (v.length > maxLength) return EmailValidationError.tooLong;
    if (!_regex.hasMatch(v)) return EmailValidationError.invalid;
    return null;
  }
}
