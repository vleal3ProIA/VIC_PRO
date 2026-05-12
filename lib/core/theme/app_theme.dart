import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:myapp/core/theme/app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => FlexThemeData.light(
        colors: const FlexSchemeColor(
          primary: AppColors.primary,
          primaryContainer: AppColors.primaryDark,
          secondary: AppColors.secondary,
          secondaryContainer: AppColors.secondary,
          tertiary: AppColors.info,
          tertiaryContainer: AppColors.info,
          appBarColor: AppColors.surface,
          error: AppColors.error,
        ),
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 7,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 10,
          useM2StyleDividerInM3: true,
          inputDecoratorRadius: 12,
          inputDecoratorBorderType: FlexInputBorderType.outline,
          elevatedButtonRadius: 12,
          filledButtonRadius: 12,
          outlinedButtonRadius: 12,
          textButtonRadius: 12,
          cardRadius: 20,
          dialogRadius: 20,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(),
      );

  static ThemeData get dark => FlexThemeData.dark(
        colors: const FlexSchemeColor(
          primary: AppColors.primary,
          primaryContainer: AppColors.primaryDark,
          secondary: AppColors.secondary,
          secondaryContainer: AppColors.secondary,
          tertiary: AppColors.info,
          tertiaryContainer: AppColors.info,
          appBarColor: AppColors.surfaceDark,
          error: AppColors.error,
        ),
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 13,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 20,
          useM2StyleDividerInM3: true,
          inputDecoratorRadius: 12,
          inputDecoratorBorderType: FlexInputBorderType.outline,
          elevatedButtonRadius: 12,
          filledButtonRadius: 12,
          outlinedButtonRadius: 12,
          textButtonRadius: 12,
          cardRadius: 20,
          dialogRadius: 20,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      );
}
