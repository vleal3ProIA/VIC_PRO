import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/router/nav_helpers.dart';

/// Tests del helper `context.popOrGo(fallback)` que reemplazo a las
/// flechas de back hardcoded en 38 paginas.
///
/// Comportamiento esperado:
///   - Si hay historia que popear -> `pop()` (vuelve a la pantalla real).
///   - Si NO hay historia (deep link / pestanya nueva) -> `goNamed(fallback)`.
void main() {
  GoRouter buildRouter({required String initialLocation}) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/a',
          name: 'a',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('PAGE A')),
          ),
        ),
        GoRoute(
          path: '/b',
          name: 'b',
          builder: (context, __) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('PAGE B'),
                  ElevatedButton(
                    onPressed: () => context.push('/c'),
                    child: const Text('push C'),
                  ),
                ],
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/c',
          name: 'c',
          builder: (context, __) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('PAGE C'),
                  ElevatedButton(
                    // Back: vuelve a B si hay historia, sino a 'a'.
                    onPressed: () => context.popOrGo('a'),
                    child: const Text('back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  testWidgets('con historia → pop() vuelve a la pantalla anterior real',
      (tester) async {
    final router = buildRouter(initialLocation: '/b');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Estamos en B. Vamos a C con push (crea historia).
    await tester.tap(find.text('push C'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE C'), findsOneWidget);

    // Back desde C: hay historia → pop → volvemos a B (NO a la fallback 'a').
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsOneWidget);
    expect(find.text('PAGE A'), findsNothing);
  });

  testWidgets('sin historia → goNamed(fallback)', (tester) async {
    // Entramos directamente a /c (deep link), sin pasar por B.
    final router = buildRouter(initialLocation: '/c');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('PAGE C'), findsOneWidget);

    // Back: no hay nada que popear → fallback a 'a'.
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE A'), findsOneWidget);
  });
}
