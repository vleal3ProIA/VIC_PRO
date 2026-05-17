import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:myapp/core/theme/app_colors.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Tema light + dark generados con FlexColorScheme.
///
/// **Decisiones de diseño**:
/// - **Brand color** = `AppColors.primary` (azul) — mantiene el branding
///   coherente con login/welcome.
/// - **M3** activado, pero con M2-style dividers (más visibles, ayudan
///   en listas densas tipo `/admin`).
/// - **Radii** consistentes con `AppRadii.md` (12) para inputs/buttons,
///   `AppRadii.lg` (20) para cards y dialogs.
/// - **Tipografía** Inter (vía GoogleFonts) — variable font, buena
///   legibilidad multi-idioma.
/// - **Density** comfortable cross-platform — Flutter por defecto es
///   compact en web/desktop y eso queda muy denso. Igualamos a iOS.
/// - **SnackBars** floating con radii consistentes (no por defecto, que
///   son cuadrados pegados al borde).
class AppTheme {
  AppTheme._();

  static ThemeData get light => _baseTheme(
        scheme: const FlexSchemeColor(
          primary: AppColors.primary,
          primaryContainer: AppColors.primaryDark,
          secondary: AppColors.secondary,
          secondaryContainer: AppColors.secondary,
          tertiary: AppColors.info,
          tertiaryContainer: AppColors.info,
          appBarColor: AppColors.surface,
          error: AppColors.error,
        ),
        isDark: false,
        baseTextTheme: GoogleFonts.interTextTheme(),
      );

  static ThemeData get dark => _baseTheme(
        scheme: const FlexSchemeColor(
          primary: AppColors.primary,
          primaryContainer: AppColors.primaryDark,
          secondary: AppColors.secondary,
          secondaryContainer: AppColors.secondary,
          tertiary: AppColors.info,
          tertiaryContainer: AppColors.info,
          appBarColor: AppColors.surfaceDark,
          error: AppColors.error,
        ),
        isDark: true,
        baseTextTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      );

  /// Common config compartido entre light y dark. Centralizar aquí evita
  /// que se desincronicen los dos modos al iterar el diseño.
  static ThemeData _baseTheme({
    required FlexSchemeColor scheme,
    required bool isDark,
    required TextTheme baseTextTheme,
  }) {
    final flexFactory =
        isDark ? FlexThemeData.dark : FlexThemeData.light;
    final base = flexFactory(
      colors: scheme,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: isDark ? 13 : 7,
      subThemesData: FlexSubThemesData(
        blendOnLevel: isDark ? 20 : 10,
        useM2StyleDividerInM3: true,
        inputDecoratorRadius: AppRadii.md,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        elevatedButtonRadius: AppRadii.md,
        filledButtonRadius: AppRadii.md,
        outlinedButtonRadius: AppRadii.md,
        textButtonRadius: AppRadii.md,
        cardRadius: AppRadii.lg,
        dialogRadius: AppRadii.lg,
        // Levantar un poco las cards en dark para que destaquen del fondo.
        cardElevation: isDark ? 1.5 : 0,
        // Snackbars floating con radii consistentes.
        snackBarRadius: AppRadii.md,
        snackBarElevation: 4,
        // Chips más legibles.
        chipRadius: AppRadii.sm,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      textTheme: baseTextTheme,
    );

    // Refinamientos post-FCS que el builder no expone limpio.
    return base.copyWith(
      // Page transitions consistentes en web (default es slide horizontal
      // chocando con la URL bar; fade es más natural para una SPA).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      // SnackBar floating + duration controlada por tokens.
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
      ),
      // Divider más sutil en dark.
      dividerTheme: base.dividerTheme.copyWith(
        thickness: 1,
        color: base.dividerTheme.color?.withValues(alpha: isDark ? 0.18 : 0.12),
      ),
    );
  }
}
