import 'package:flutter/material.dart';

/// Design tokens de la app. **Fuente única** de spacing, radii, durations
/// y elevations.
///
/// **Cómo se usa**: en cualquier widget importa este archivo y referencia
/// `AppSpacing.md` en vez de literales tipo `16.0`. Cambios futuros de
/// escala (densidad compacta para móvil, expansión para pantallas
/// grandes) se hacen aquí en un sitio.
///
/// **Por qué clases con `static const` y no theme extensions**:
/// las theme extensions son más "puras" Material, pero requieren
/// `Theme.of(context).extension<X>()` en cada uso — sobrecarga visual
/// para algo que NO cambia entre light/dark. Tokens estructurales como
/// spacing son globales por definición.

/// Escala de espaciado base 4. Inspirada en Tailwind / Material 3.
class AppSpacing {
  AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  // EdgeInsets convenientes — evitan crear `const EdgeInsets.all(16)` en
  // cada widget.
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);

  static const EdgeInsets horizontalSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: lg);

  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);

  // SizedBox helpers para separar widgets en Column/Row.
  static const Widget gapXs = SizedBox(height: xs, width: xs);
  static const Widget gapSm = SizedBox(height: sm, width: sm);
  static const Widget gapMd = SizedBox(height: md, width: md);
  static const Widget gapLg = SizedBox(height: lg, width: lg);
  static const Widget gapXl = SizedBox(height: xl, width: xl);
}

/// Radii consistentes. Coherentes con los valores definidos en
/// `AppTheme` para inputs/buttons/cards/dialogs.
class AppRadii {
  AppRadii._();
  static const double sm = 6;
  static const double md = 12;
  static const double lg = 20;
  // "Pill"-shaped: usamos uno grande, no `double.infinity` (Flutter no lo
  // acepta en BorderRadius).
  static const double pill = 999;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));
}

/// Duraciones para animaciones. Mantener corta la mayoría — micro-
/// interacciones rápidas se sienten más "responsive".
class AppDurations {
  AppDurations._();
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  /// Para snackbars y banners informativos.
  static const Duration snack = Duration(seconds: 3);

  /// Para snackbars de error que requieren atención.
  static const Duration snackLong = Duration(seconds: 5);
}

/// Anchos máximos de contenido para layouts centrados. Evita líneas
/// excesivamente largas en pantallas grandes (mejor legibilidad).
class AppMaxWidths {
  AppMaxWidths._();
  /// Para forms y dialogs anchos (se mantiene acotado: auth/diálogos).
  static const double form = 480;
  /// Listas de cards / tablas admin. En web aprovechamos el ANCHO COMPLETO
  /// del área de contenido (antes 880).
  static const double content = double.infinity;
  /// Layouts wide tipo dashboard. Ancho completo en web (antes 1200).
  static const double wide = double.infinity;
}

/// Breakpoints responsive. Mobile-first: usar `>= sm` para "tablet+",
/// `>= md` para "desktop pequeño", etc. Compatible con la convención
/// de TailwindCSS / Bootstrap para que el equipo lo encuentre familiar.
///
/// Ejemplos de uso:
/// ```dart
/// final w = MediaQuery.of(context).size.width;
/// if (w >= AppBreakpoints.md) {
///   // layout desktop
/// } else {
///   // layout mobile
/// }
/// ```
class AppBreakpoints {
  AppBreakpoints._();
  /// Móvil pequeño (< 640): un solo column, padding mínimo.
  static const double sm = 640;
  /// Tablet / móvil grande: 2 columnas, padding medio.
  static const double md = 768;
  /// Laptop pequeña: 3 columnas, sidebar opcional.
  static const double lg = 1024;
  /// Desktop estándar: layout completo con sidebar.
  static const double xl = 1280;
  /// Pantalla grande: cuidado con líneas demasiado largas (usar AppMaxWidths).
  static const double xxl = 1536;

  /// `true` si el ancho actual califica como "desktop" (>= lg).
  static bool isDesktop(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= lg;

  /// `true` si es tablet (>= md y < lg).
  static bool isTablet(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    return w >= md && w < lg;
  }

  /// `true` si el ancho actual califica como "mobile" (< md).
  static bool isMobile(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width < md;
}

/// Sombras premium estilo Stripe / Linear / Notion. Sombras suaves,
/// difusas, con offset corto en Y. **Nunca usar `Colors.black` puro** —
/// siempre con opacity baja para que se vea "premium" en lugar de
/// "Material elevation cruda".
///
/// Cada nivel tiene una variante para light y dark. En dark mode las
/// sombras son menos visibles (fondo ya oscuro) pero seguimos teniendo
/// para mantener separación visual.
///
/// Uso típico:
/// ```dart
/// Container(
///   decoration: BoxDecoration(
///     borderRadius: AppRadii.brMd,
///     boxShadow: AppShadows.card(theme.brightness),
///   ),
///   ...
/// )
/// ```
class AppShadows {
  AppShadows._();

  /// Sombra mínima para elementos que necesitan separación pero NO
  /// elevación (ej. botones secondary).
  static List<BoxShadow> sm(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, isDark ? 0.20 : 0.04),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// Sombra para cards estándar. Suave, 12px de blur. Lo más usado.
  static List<BoxShadow> card(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, isDark ? 0.25 : 0.05),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, isDark ? 0.10 : 0.02),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// Sombra elevada para elementos flotantes (popovers, dropdowns, FAB).
  static List<BoxShadow> elevated(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, isDark ? 0.35 : 0.08),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, isDark ? 0.15 : 0.03),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Sombra máxima para modales y dialogs centrados.
  static List<BoxShadow> modal(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, isDark ? 0.50 : 0.12),
        blurRadius: 40,
        offset: const Offset(0, 12),
      ),
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, isDark ? 0.25 : 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
  }
}
