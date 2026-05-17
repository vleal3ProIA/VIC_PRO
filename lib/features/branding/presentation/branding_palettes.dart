import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// Una paleta = combinación de colores (primary + secondary + tertiary)
/// que el admin puede elegir desde `/admin/app-branding` o desde el
/// wizard `/setup`. El slug se guarda en `app_branding.color_palette`
/// y al boot la app genera el tema correspondiente.
///
/// 5 paletas curadas que cubren los verticales más comunes:
///   - `blue`    : SaaS corporativo (default — el original del proyecto)
///   - `green`   : wellness / eco / fintech amable
///   - `purple`  : premium / creative
///   - `orange`  : retail / comida / energético
///   - `mono`    : monocromo gris — profesional / minimalista
class BrandingPalette {
  const BrandingPalette({
    required this.slug,
    required this.label,
    required this.lightScheme,
    required this.darkScheme,
    required this.previewColor,
  });

  final String slug;
  final String label;
  final FlexSchemeColor lightScheme;
  final FlexSchemeColor darkScheme;

  /// Color representativo que se muestra en el selector (chip / círculo).
  final Color previewColor;
}

class BrandingPalettes {
  BrandingPalettes._();

  // ─────────────────────── Blue (default) ───────────────────────
  static const _blueLight = FlexSchemeColor(
    primary: Color(0xFF2563EB),         // blue-600
    primaryContainer: Color(0xFF1D4ED8),
    secondary: Color(0xFF14B8A6),       // teal-500
    secondaryContainer: Color(0xFF0F766E),
    tertiary: Color(0xFF6366F1),        // indigo-500
    tertiaryContainer: Color(0xFF4338CA),
    appBarColor: Color(0xFFFFFFFF),
    error: Color(0xFFDC2626),
  );
  static const _blueDark = FlexSchemeColor(
    primary: Color(0xFF60A5FA),         // blue-400 para contraste en dark
    primaryContainer: Color(0xFF1E40AF),
    secondary: Color(0xFF2DD4BF),
    secondaryContainer: Color(0xFF0F766E),
    tertiary: Color(0xFF818CF8),
    tertiaryContainer: Color(0xFF3730A3),
    appBarColor: Color(0xFF0F172A),
    error: Color(0xFFEF4444),
  );

  // ─────────────────────── Green (wellness/eco) ───────────────────────
  static const _greenLight = FlexSchemeColor(
    primary: Color(0xFF059669),         // emerald-600
    primaryContainer: Color(0xFF047857),
    secondary: Color(0xFFCA8A04),       // yellow-600
    secondaryContainer: Color(0xFFA16207),
    tertiary: Color(0xFF0891B2),        // cyan-600
    tertiaryContainer: Color(0xFF155E75),
    appBarColor: Color(0xFFFFFFFF),
    error: Color(0xFFDC2626),
  );
  static const _greenDark = FlexSchemeColor(
    primary: Color(0xFF34D399),
    primaryContainer: Color(0xFF065F46),
    secondary: Color(0xFFEAB308),
    secondaryContainer: Color(0xFF854D0E),
    tertiary: Color(0xFF22D3EE),
    tertiaryContainer: Color(0xFF155E75),
    appBarColor: Color(0xFF0F1E14),
    error: Color(0xFFEF4444),
  );

  // ─────────────────────── Purple (premium/creative) ───────────────────────
  static const _purpleLight = FlexSchemeColor(
    primary: Color(0xFF7C3AED),         // violet-600
    primaryContainer: Color(0xFF6D28D9),
    secondary: Color(0xFFEC4899),       // pink-500
    secondaryContainer: Color(0xFFBE185D),
    tertiary: Color(0xFFF59E0B),        // amber-500
    tertiaryContainer: Color(0xFFB45309),
    appBarColor: Color(0xFFFFFFFF),
    error: Color(0xFFDC2626),
  );
  static const _purpleDark = FlexSchemeColor(
    primary: Color(0xFFA78BFA),
    primaryContainer: Color(0xFF5B21B6),
    secondary: Color(0xFFF472B6),
    secondaryContainer: Color(0xFF9D174D),
    tertiary: Color(0xFFFBBF24),
    tertiaryContainer: Color(0xFF92400E),
    appBarColor: Color(0xFF1A0E2A),
    error: Color(0xFFEF4444),
  );

  // ─────────────────────── Orange (retail/food/energía) ───────────────────────
  static const _orangeLight = FlexSchemeColor(
    primary: Color(0xFFEA580C),         // orange-600
    primaryContainer: Color(0xFFC2410C),
    secondary: Color(0xFF65A30D),       // lime-600
    secondaryContainer: Color(0xFF4D7C0F),
    tertiary: Color(0xFF0EA5E9),        // sky-500
    tertiaryContainer: Color(0xFF0369A1),
    appBarColor: Color(0xFFFFFFFF),
    error: Color(0xFFB91C1C),
  );
  static const _orangeDark = FlexSchemeColor(
    primary: Color(0xFFFB923C),
    primaryContainer: Color(0xFF9A3412),
    secondary: Color(0xFFA3E635),
    secondaryContainer: Color(0xFF3F6212),
    tertiary: Color(0xFF38BDF8),
    tertiaryContainer: Color(0xFF075985),
    appBarColor: Color(0xFF1F1108),
    error: Color(0xFFEF4444),
  );

  // ─────────────────────── Mono (gris profesional) ───────────────────────
  static const _monoLight = FlexSchemeColor(
    primary: Color(0xFF374151),         // gray-700
    primaryContainer: Color(0xFF1F2937),
    secondary: Color(0xFF6B7280),
    secondaryContainer: Color(0xFF4B5563),
    tertiary: Color(0xFF0EA5E9),        // sky para acento solo donde haga falta
    tertiaryContainer: Color(0xFF0369A1),
    appBarColor: Color(0xFFFFFFFF),
    error: Color(0xFFB91C1C),
  );
  static const _monoDark = FlexSchemeColor(
    primary: Color(0xFFE5E7EB),         // gray-200 para dark, alto contraste
    primaryContainer: Color(0xFF374151),
    secondary: Color(0xFF9CA3AF),
    secondaryContainer: Color(0xFF4B5563),
    tertiary: Color(0xFF38BDF8),
    tertiaryContainer: Color(0xFF0369A1),
    appBarColor: Color(0xFF111827),
    error: Color(0xFFEF4444),
  );

  /// Lista en el ORDEN que aparece en el selector de la UI.
  static const List<BrandingPalette> all = [
    BrandingPalette(
      slug: 'blue',
      label: 'Blue',
      lightScheme: _blueLight,
      darkScheme: _blueDark,
      previewColor: Color(0xFF2563EB),
    ),
    BrandingPalette(
      slug: 'green',
      label: 'Green',
      lightScheme: _greenLight,
      darkScheme: _greenDark,
      previewColor: Color(0xFF059669),
    ),
    BrandingPalette(
      slug: 'purple',
      label: 'Purple',
      lightScheme: _purpleLight,
      darkScheme: _purpleDark,
      previewColor: Color(0xFF7C3AED),
    ),
    BrandingPalette(
      slug: 'orange',
      label: 'Orange',
      lightScheme: _orangeLight,
      darkScheme: _orangeDark,
      previewColor: Color(0xFFEA580C),
    ),
    BrandingPalette(
      slug: 'mono',
      label: 'Mono',
      lightScheme: _monoLight,
      darkScheme: _monoDark,
      previewColor: Color(0xFF374151),
    ),
  ];

  /// Default cuando el slug guardado no existe (paleta retirada, typo
  /// manual en la BD, etc.).
  static const BrandingPalette fallback = BrandingPalette(
    slug: 'blue',
    label: 'Blue',
    lightScheme: _blueLight,
    darkScheme: _blueDark,
    previewColor: Color(0xFF2563EB),
  );

  /// Busca por slug; cae a [fallback] si no existe.
  static BrandingPalette bySlug(String slug) {
    for (final p in all) {
      if (p.slug == slug) return p;
    }
    return fallback;
  }
}
