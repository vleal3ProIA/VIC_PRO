// ============================================================================
// Helpers de navegacion (Bug-arrow-back)
// ----------------------------------------------------------------------------
// Hasta ahora, casi todas las paginas hacian su flecha de "volver" con
// `context.goNamed(RouteNames.<destino_fijo>)`. Eso teletransporta al
// usuario a un destino hardcoded en vez de devolverlo al sitio del que
// venia, lo que rompe la metafora basica de "atras":
//
//   - /notifications -> back -> te ibas a /account-settings (hardcoded)
//     aunque hubieras llegado a /notifications desde /home.
//   - /status        -> back -> te ibas a /welcome (hardcoded), donde
//     el boton "Iniciar sesion" te re-entraba a /home via el guard
//     `publicOnly`. Parecia auto-login pero era solo el guard.
//   - Misma forma en ~30 paginas.
//
// **Fix**: usar el nav stack real con un fallback sensato.
//
//   context.popOrGo(RouteNames.fallback)
//
// hace lo correcto en ambos casos:
//   - Si hay historia (el comun) -> `pop()`, vuelves al sitio real.
//   - Si NO hay historia (deep link, URL pegada en pestanya nueva,
//     refresh) -> `goNamed(fallback)` como destino razonable.
//
// **Por que un extension method y no una funcion suelta**: hace los
// callsites igual de cortos que el original `context.goNamed(...)`.
// Sustitucion mecanica, 1 a 1, sin imports nuevos en cada page (el
// barrel `router/route_names.dart` lo re-exporta).
// ============================================================================

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension AppNavExtensions on BuildContext {
  /// Vuelve a la pantalla anterior usando el nav stack real. Si no
  /// hay nada que popear (el user abrio esta URL directamente / hizo
  /// refresh / vino desde un enlace externo), navega a `fallbackRoute`.
  ///
  /// Uso tipico en la flecha de back de un AppBar:
  /// ```dart
  /// IconButton(
  ///   icon: const Icon(Icons.arrow_back),
  ///   onPressed: () => context.popOrGo(RouteNames.accountSettings),
  /// )
  /// ```
  ///
  /// `fallbackRoute` debe ser un `RouteNames.X` (no un path crudo).
  void popOrGo(String fallbackRoute) {
    if (canPop()) {
      pop();
    } else {
      goNamed(fallbackRoute);
    }
  }
}
