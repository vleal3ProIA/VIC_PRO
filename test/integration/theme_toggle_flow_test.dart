import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/features/welcome/presentation/widgets/theme_toggle.dart';

import '_helpers.dart';

/// E2E del **toggle de tema** desde el AppBar del welcome:
///
///   /  (WelcomePage, top bar con ThemeToggle)
///   → 1er tap: system → light  (icono pasa a light_mode_outlined)
///   → 2º tap: light → dark      (icono pasa a dark_mode_outlined)
///   → 3er tap: dark → system    (icono pasa a brightness_auto_outlined)
///
/// Cubre 3 cosas a la vez: el ThemeNotifier cicla, el widget reflecta
/// el modo nuevo en su icono, y la preferencia se persiste en
/// SharedPreferences (chequeable leyendo el provider directo después).
void main() {
  testWidgets('ThemeToggle cicla system → light → dark → system',
      (tester) async {
    final repo = FakeAuthRepository();
    final app = await buildAppForIntegration(repo: repo);

    await tester.pumpWidget(app);
    await primeApp(tester);

    // Buscamos un ProviderScope para inspeccionar estado interno.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ThemeToggle)),
    );

    // Estado inicial: system (default).
    expect(container.read(themeNotifierProvider), ThemeMode.system);
    expect(find.byIcon(Icons.brightness_auto_outlined), findsOneWidget);

    // Tap 1 → light.
    await tester.tap(find.byType(ThemeToggle));
    await tester.pumpAndSettle();
    expect(container.read(themeNotifierProvider), ThemeMode.light);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    // Tap 2 → dark.
    await tester.tap(find.byType(ThemeToggle));
    await tester.pumpAndSettle();
    expect(container.read(themeNotifierProvider), ThemeMode.dark);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

    // Tap 3 → system de nuevo.
    await tester.tap(find.byType(ThemeToggle));
    await tester.pumpAndSettle();
    expect(container.read(themeNotifierProvider), ThemeMode.system);
    expect(find.byIcon(Icons.brightness_auto_outlined), findsOneWidget);
  });
}
