// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'myapp';

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get signInToContinue => 'Sign in to continue';

  @override
  String welcomeUser(String name) {
    return 'Welcome, $name';
  }

  @override
  String get errorRequired => 'This field is required';

  @override
  String get errorInvalidEmail => 'Invalid email';

  @override
  String errorPasswordTooShort(int count) {
    return 'Password must be at least $count characters';
  }

  @override
  String get errorUnknown => 'Unexpected error';

  @override
  String get errorNoConnection => 'No internet connection';
}
