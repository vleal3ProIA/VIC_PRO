import 'package:formz/formz.dart';

/// Tipos de error del nombre de usuario.
/// Los strings de UI se resuelven en la capa de presentación vía l10n.
enum UsernameValidationError {
  empty,
  tooShort,
  tooLong,
  invalidChars,
}

/// Reglas:
/// - 3..30 caracteres.
/// - Solo letras (Unicode), números, `_`, `-`, `.`.
/// - No empieza ni acaba con `_`, `-` o `.`.
/// - No dos separadores seguidos.
class Username extends FormzInput<String, UsernameValidationError> {
  const Username.pure() : super.pure('');
  const Username.dirty([super.value = '']) : super.dirty();

  static const int minLength = 3;
  static const int maxLength = 30;

  // Caracteres permitidos: letra Unicode, dígito, _ - .
  static final RegExp _allowed = RegExp(r'^[\p{L}\p{N}._-]+$', unicode: true);

  // No empieza/acaba con separador y no tiene dos separadores seguidos.
  static final RegExp _wellFormed = RegExp(
    r'^(?![._-])(?!.*[._-]{2})[\p{L}\p{N}._-]+(?<![._-])$',
    unicode: true,
  );

  @override
  UsernameValidationError? validator(String value) {
    if (value.isEmpty) return UsernameValidationError.empty;
    if (value.length < minLength) return UsernameValidationError.tooShort;
    if (value.length > maxLength) return UsernameValidationError.tooLong;
    if (!_allowed.hasMatch(value) || !_wellFormed.hasMatch(value)) {
      return UsernameValidationError.invalidChars;
    }
    return null;
  }
}
