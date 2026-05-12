import 'package:flutter_test/flutter_test.dart';
import 'package:formz/formz.dart';
import 'package:myapp/core/validation/email.dart';
import 'package:myapp/core/validation/password.dart';
import 'package:myapp/core/validation/password_confirmation.dart';
import 'package:myapp/core/validation/username.dart';

void main() {
  group('Username validator', () {
    test('empty', () {
      expect(
        const Username.dirty('').error,
        UsernameValidationError.empty,
      );
    });
    test('too short / too long', () {
      expect(
        const Username.dirty('ab').error,
        UsernameValidationError.tooShort,
      );
      expect(
        Username.dirty('a' * 31).error,
        UsernameValidationError.tooLong,
      );
    });
    test('invalid chars', () {
      expect(
        const Username.dirty('hi!').error,
        UsernameValidationError.invalidChars,
      );
      expect(
        const Username.dirty('.starts').error,
        UsernameValidationError.invalidChars,
      );
      expect(
        const Username.dirty('two..dots').error,
        UsernameValidationError.invalidChars,
      );
    });
    test('valid', () {
      expect(const Username.dirty('john_doe').isValid, isTrue);
      expect(const Username.dirty('María.López-3').isValid, isTrue);
      expect(const Username.dirty('Ñandú99').isValid, isTrue);
    });
  });

  group('Email validator', () {
    test('rejects empty / invalid', () {
      expect(const Email.dirty('').error, EmailValidationError.empty);
      expect(const Email.dirty('foo').error, EmailValidationError.invalid);
      expect(const Email.dirty('foo@').error, EmailValidationError.invalid);
      expect(const Email.dirty('@bar.com').error, EmailValidationError.invalid);
    });
    test('accepts valid', () {
      expect(const Email.dirty('a@b.io').isValid, isTrue);
      expect(const Email.dirty('john.doe+tag@sub.example.com').isValid, isTrue);
    });
  });

  group('Password validator', () {
    test('rules enforced individually', () {
      expect(
        const Password.dirty('').error,
        PasswordValidationError.empty,
      );
      expect(
        const Password.dirty('Ab1!aaa').error,
        PasswordValidationError.tooShort,
      );
      expect(
        const Password.dirty('ALLUPPER1!').error,
        PasswordValidationError.missingLowercase,
      );
      expect(
        const Password.dirty('alllower1!').error,
        PasswordValidationError.missingUppercase,
      );
      expect(
        const Password.dirty('NoDigits!').error,
        PasswordValidationError.missingDigit,
      );
      expect(
        const Password.dirty('NoSpecial1').error,
        PasswordValidationError.missingSpecial,
      );
    });
    test('valid password passes', () {
      expect(const Password.dirty('Aa1!aaaa').isValid, isTrue);
      expect(const Password.dirty('Str0ng#Pass').isValid, isTrue);
    });
    test('strength scoring', () {
      expect(Password.strength(''), 0);
      expect(Password.strength('abcdefgh'), greaterThanOrEqualTo(1));
      expect(Password.strength('Aa1!aaaa'), 4);
    });
  });

  group('PasswordConfirmation validator', () {
    test('empty', () {
      expect(
        const PasswordConfirmation.dirty(password: 'Aa1!aaaa').error,
        PasswordConfirmationValidationError.empty,
      );
    });
    test('mismatch', () {
      expect(
        const PasswordConfirmation.dirty(
          password: 'Aa1!aaaa',
          value: 'other',
        ).error,
        PasswordConfirmationValidationError.mismatch,
      );
    });
    test('match is valid', () {
      expect(
        const PasswordConfirmation.dirty(
          password: 'Aa1!aaaa',
          value: 'Aa1!aaaa',
        ).isValid,
        isTrue,
      );
    });
  });

  group('Formz.validate composite', () {
    test('all valid → form valid', () {
      const u = Username.dirty('john_doe');
      const e = Email.dirty('john@example.com');
      const p = Password.dirty('Aa1!aaaa');
      const c = PasswordConfirmation.dirty(
        password: 'Aa1!aaaa',
        value: 'Aa1!aaaa',
      );
      expect(Formz.validate([u, e, p, c]), isTrue);
    });
    test('one invalid → form invalid', () {
      const u = Username.dirty('ok_name');
      const e = Email.dirty('bad-email');
      const p = Password.dirty('Aa1!aaaa');
      const c = PasswordConfirmation.dirty(
        password: 'Aa1!aaaa',
        value: 'Aa1!aaaa',
      );
      expect(Formz.validate([u, e, p, c]), isFalse);
    });
  });
}
