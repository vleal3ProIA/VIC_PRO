// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'myapp';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get email => 'Correo electrónico';

  @override
  String get password => 'Contraseña';

  @override
  String get welcomeBack => 'Bienvenido';

  @override
  String get signInToContinue => 'Inicia sesión para continuar';

  @override
  String welcomeUser(String name) {
    return 'Bienvenido, $name';
  }

  @override
  String get errorRequired => 'Este campo es obligatorio';

  @override
  String get errorInvalidEmail => 'Correo no válido';

  @override
  String errorPasswordTooShort(int count) {
    return 'La contraseña debe tener al menos $count caracteres';
  }

  @override
  String get errorUnknown => 'Error inesperado';

  @override
  String get errorNoConnection => 'Sin conexión a internet';
}
