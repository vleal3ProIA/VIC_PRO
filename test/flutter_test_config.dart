import 'dart:async';

import 'package:golden_toolkit/golden_toolkit.dart';

/// Configuración global del runner de tests. Flutter detecta automáticamente
/// `test/flutter_test_config.dart` y la ejecuta antes de cualquier test.
///
/// Aquí cargamos las fuentes reales de la app (en lugar de la fuente Ahem que
/// usa Flutter en tests por defecto) para que los **golden tests** rendericen
/// con el mismo aspecto que la app real. Sin esto los goldens saldrían con
/// cajas en lugar de texto.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  return GoldenToolkit.runWithConfiguration(
    () async {
      await loadAppFonts();
      await testMain();
    },
    config: GoldenToolkitConfiguration(
      // En CI excluimos el tag `golden` (ver dart_test.yaml), así que no
      // necesitamos `skipGoldenAssertion` aquí: cuando los goldens corran,
      // queremos comparación pixel-perfect.
      enableRealShadows: true,
    ),
  );
}
