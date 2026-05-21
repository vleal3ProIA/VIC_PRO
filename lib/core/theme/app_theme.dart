import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/features/branding/presentation/branding_palettes.dart';

/// Tema light + dark generados con FlexColorScheme. La paleta de
/// colores es configurable por deploy via [BrandingPalettes] —
/// el `AppTheme` toma la paleta como parámetro y devuelve los temas
/// correspondientes.
///
/// **Decisiones de diseño**:
/// - **Brand color** viene del `BrandingPalette` activo (ver
///   `app_branding.color_palette` en BD). Default `blue`.
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

  /// Tema light para la paleta dada. Usar con [BrandingPalettes.bySlug].
  static ThemeData lightFor(BrandingPalette palette) => _baseTheme(
        scheme: palette.lightScheme,
        isDark: false,
        baseTextTheme: GoogleFonts.interTextTheme(),
      );

  /// Tema dark para la paleta dada.
  static ThemeData darkFor(BrandingPalette palette) => _baseTheme(
        scheme: palette.darkScheme,
        isDark: true,
        baseTextTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      );

  /// Atajo con la paleta por defecto. Útil para tests y para builders
  /// que aún no consumen el provider de branding.
  static ThemeData get light => lightFor(BrandingPalettes.fallback);
  static ThemeData get dark => darkFor(BrandingPalettes.fallback);

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
      // ─── Botones Premium ───
      // Subimos peso tipográfico (w600 + letter-spacing negativo, look
      // Stripe/Linear) y altura mínima cómoda en TODOS los botones de la app
      // sin tocar cada call-site. Derivamos del style que ya genera
      // FlexColorScheme (mantiene colores de la paleta + fuente Inter) y solo
      // sobre-escribimos textStyle / minimumSize / padding.
      filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStatePropertyAll(_btnTextStyle(base)),
          minimumSize: const WidgetStatePropertyAll(Size(64, 50)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStatePropertyAll(_btnTextStyle(base)),
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStatePropertyAll(_btnTextStyle(base)),
        ),
      ),
    );
  }

  /// TextStyle compartido para botones: deriva de `labelLarge` (Inter) para
  /// no perder la familia tipográfica y solo ajusta peso + tracking.
  static TextStyle _btnTextStyle(ThemeData base) =>
      (base.textTheme.labelLarge ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      );
}
