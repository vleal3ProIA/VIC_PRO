/// Barrel file de los componentes premium (PR-Premium-UI Fase 1).
library;
// ignore_for_file: directives_ordering
///
/// **Uso**: en tus pages haz `import` desde aqui en lugar de cada
/// archivo individual:
///
/// ```dart
/// import 'package:myapp/core/widgets/premium/premium.dart';
///
/// // Ahora tienes acceso a:
/// // - PremiumCard
/// // - KpiCard, KpiTrend
/// // - SectionHeader
/// ```
///
/// **Filosofia de diseno** (segun captura de inspiracion MaterialPro
/// y referencias Stripe / Linear / Notion):
/// - Minimalista, mucho aire, jerarquia visual clara.
/// - Sombras suaves (`AppShadows.card` / `elevated`), nunca elevation
///   crudo de Material.
/// - Esquinas redondeadas precisas (12px = `AppRadii.md` para cards).
/// - Animaciones cortas (150-250ms), `Curves.easeOutCubic`.
/// - Dark mode soportado: sombras + borders se ajustan automaticamente.
///
/// **Para anyadir un componente nuevo aqui**:
/// 1. Crear el archivo `core/widgets/premium/mi_componente.dart`.
/// 2. Documentar con dartdoc + ejemplo de uso.
/// 3. Soportar dark mode (leer `Theme.of(context).brightness`).
/// 4. Soportar responsive (usar `LayoutBuilder` o
///    `AppBreakpoints.isMobile/isTablet/isDesktop`).
/// 5. Exportar aqui en el barrel.

export 'kpi_card.dart';
export 'premium_card.dart';
export 'section_header.dart';
