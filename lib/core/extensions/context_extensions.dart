import 'package:flutter/material.dart';

import 'package:myapp/core/constants/app_constants.dart';
import 'package:myapp/core/utils/a11y_announcer.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;
  MediaQueryData get mq => MediaQuery.of(this);
  Size get screen => mq.size;
  AppLocalizations get l10n => AppLocalizations.of(this);

  bool get isMobile => screen.width < AppConstants.mobileBreakpoint;
  bool get isTablet =>
      screen.width >= AppConstants.mobileBreakpoint &&
      screen.width < AppConstants.tabletBreakpoint;
  bool get isDesktop => screen.width >= AppConstants.tabletBreakpoint;

  void showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colors.error : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
    // a11y: el snackbar se desvanece en 4s, pero un lector de pantalla
    // puede no haber tenido tiempo de leerlo si el usuario estaba en
    // otra región. `announce` se inyecta como aria-live polite (o
    // assertive si es error) para que el screen reader lo reproduzca
    // independientemente del foco actual.
    if (isError) {
      A11yAnnouncer.announceAssertive(this, message);
    } else {
      A11yAnnouncer.announce(this, message);
    }
  }
}
