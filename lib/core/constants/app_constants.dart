class AppConstants {
  AppConstants._();

  static const String appName = 'myapp';
  static const Duration defaultAnimation = Duration(milliseconds: 250);

  // Material 3 responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1440;

  // Password rules (used by validators + UI hints)
  static const int passwordMinLength = 8;
  static const int maxInputLength = 255;

  // Fixed card sizes — never expand to fit errors, reserve vertical space.
  static const double authCardWidth = 420;
  static const double inputErrorSlotHeight = 22;
  static const double generalErrorSlotHeight = 48;
}
