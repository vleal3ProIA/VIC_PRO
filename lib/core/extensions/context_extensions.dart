import 'package:flutter/material.dart';

import 'package:myapp/core/constants/app_constants.dart';
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
  }
}
