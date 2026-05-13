import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/core/storage/remember_aware_local_storage.dart';

/// Instancia compartida del storage de auth. La misma que se pasa a
/// `Supabase.initialize` en `main.dart` — al ser stateless con respecto a
/// `SharedPreferences`, dos instancias dan el mismo resultado, pero es más
/// limpio resolverlo siempre por aquí.
final rememberAwareStorageProvider = Provider<RememberAwareLocalStorage>(
  (ref) => RememberAwareLocalStorage(ref.watch(sharedPreferencesProvider)),
);
