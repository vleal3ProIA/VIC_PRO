import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Inicializado en `main()` con `overrideWithValue` para evitar awaits en árbol.
/// Si alguien lo lee antes de la inicialización lanza explícitamente.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope at main().',
  );
});
