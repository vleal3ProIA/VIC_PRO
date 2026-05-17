import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

/// Smoke test de a11y: en las pantallas públicas con IconButton (welcome,
/// login, register, forgot-password, magic-link, otp), ningún
/// IconButton debe tener `tooltip` null o vacío.
///
/// Cubre regresiones donde alguien añade un IconButton nuevo y olvida
/// el tooltip — sin tooltip el botón es invisible para lectores de
/// pantalla (WCAG 4.1.2 falla) y no muestra ayuda al hover.
///
/// El test NO impone que **todos** los IconButtons de la app pasen el
/// chequeo (algunos van en pantallas privadas que requieren Supabase
/// real); cubre lo público que es lo que ve un visitante anónimo.
void main() {
  for (final route in _routesToAudit) {
    testWidgets('IconButtons en $route tienen tooltip', (tester) async {
      final repo = FakeAuthRepository();
      final app = await buildAppForIntegration(
        repo: repo,
        initialLocation: route,
      );

      await tester.pumpWidget(app);
      await primeApp(tester);

      final iconButtons = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .toList(growable: false);
      expect(
        iconButtons,
        isNotEmpty,
        reason: 'esperaba al menos 1 IconButton en $route — '
            'si la página ya no tiene ninguno, quita la ruta del test',
      );

      for (final button in iconButtons) {
        final tooltip = button.tooltip;
        expect(
          tooltip,
          isNotNull,
          reason: 'IconButton sin tooltip en $route '
              '(icon: ${button.icon.runtimeType})',
        );
        expect(
          tooltip!.trim(),
          isNotEmpty,
          reason: 'IconButton con tooltip vacío en $route '
              '(icon: ${button.icon.runtimeType})',
        );
      }
    });
  }
}

const _routesToAudit = [
  '/',
  '/login',
  '/register',
  '/forgot-password',
  '/magic-link',
  '/otp',
];
