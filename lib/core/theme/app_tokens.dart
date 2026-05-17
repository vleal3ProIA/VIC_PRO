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
  /// Para forms y dialogs anchos.
  static const double form = 480;
  /// Para listas de cards (catálogo de planes, admin tables, etc.).
  static const double content = 880;
  /// Para layouts wide tipo dashboard con paneles laterales.
  static const double wide = 1200;
}
