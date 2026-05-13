import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'remember_storage_stub.dart'
    if (dart.library.js_interop) 'remember_storage_web.dart';

/// Implementación de `LocalStorage` para `supabase_flutter` que conmuta el
/// backend según la preferencia "Recordar sesión":
///
/// - `rememberMe = true`  → `localStorage` del navegador (persistente entre
///   sesiones del navegador, sobrevive a cerrar pestaña).
/// - `rememberMe = false` → `sessionStorage` del navegador (se borra al
///   cerrar la pestaña/navegador). Es el default.
///
/// La flag se persiste en `SharedPreferences` para sobrevivir a recargas.
/// En no-web esta clase se comporta como no-op y el SDK usa su storage
/// por defecto.
class RememberAwareLocalStorage extends LocalStorage {
  RememberAwareLocalStorage(this._prefs);

  final SharedPreferences _prefs;

  /// Clave bajo la que guardamos la sesión. La elegimos nosotros para no
  /// chocar con el storage por defecto del SDK (que usa Hive).
  static const String _storageKey = 'sb-myapp-auth-token';
  static const String _rememberPref = 'auth_remember_me';

  /// `true` si el usuario marcó "Recordar sesión" en el último login.
  bool get rememberMe => _prefs.getBool(_rememberPref) ?? false;

  /// Cambia la preferencia y, si hay una sesión activa, la mueve al
  /// storage correspondiente para que el cambio surta efecto sin
  /// necesidad de un nuevo login.
  Future<void> setRememberMe({required bool value}) async {
    final previous = rememberMe;
    await _prefs.setBool(_rememberPref, value);
    if (!kIsWeb || previous == value) return;
    final current = WebStorageHelper.getItem(
      _storageKey,
      persistent: previous,
    );
    if (current != null) {
      WebStorageHelper.setItem(_storageKey, current, persistent: value);
    }
  }

  // --- LocalStorage interface ------------------------------------------------

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async {
    if (!kIsWeb) return null;
    return WebStorageHelper.getItem(_storageKey, persistent: rememberMe);
  }

  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (!kIsWeb) return;
    WebStorageHelper.setItem(
      _storageKey,
      persistSessionString,
      persistent: rememberMe,
    );
  }

  @override
  Future<void> removePersistedSession() async {
    if (!kIsWeb) return;
    WebStorageHelper.removeItem(_storageKey);
  }
}
