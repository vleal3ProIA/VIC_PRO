import 'package:formz/formz.dart';

enum PasswordConfirmationValidationError { empty, mismatch }

/// `FormzInput` con valor compuesto: (passwordOriginal, confirmacion).
/// Permite validar contra la contraseña original sin acoplar a otra clase.
class PasswordConfirmation
    extends FormzInput<String, PasswordConfirmationValidationError> {
  const PasswordConfirmation.pure({this.password = ''}) : super.pure('');
  const PasswordConfirmation.dirty({required this.password, String value = ''})
      : super.dirty(value);

  final String password;

  @override
  PasswordConfirmationValidationError? validator(String value) {
    if (value.isEmpty) return PasswordConfirmationValidationError.empty;
    if (value != password) {
      return PasswordConfirmationValidationError.mismatch;
    }
    return null;
  }
}
