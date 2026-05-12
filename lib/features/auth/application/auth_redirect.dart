import 'package:flutter/foundation.dart';

enum AuthRedirectType { signup, recovery }

/// URL absoluta a la que Supabase redirige tras el click en un email de auth.
///
/// En web lee el origen del navegador (sin path, sin query, sin fragment) y
/// le añade `/auth/callback?type=...`. El callback page lee ese `type` para
/// distinguir si viene de un signup o de un reset de password.
///
/// **Por qué `Uri.base.origin` y no `Uri.base.replace(path: '')`**:
/// `Uri.replace(path: '')` no garantiza eliminar el path en todos los casos
/// (depende del path original). `origin` devuelve exactamente
/// `scheme://host:port`, que es lo único que queremos como base.
///
/// IMPORTANTE: el origen debe estar listado en
/// **Supabase Dashboard → Authentication → URL Configuration → Redirect URLs**
/// con un patrón que incluya `/auth/callback` (p. ej. `http://localhost:5000/**`).
class AuthRedirect {
  AuthRedirect._();

  static const String callbackPath = '/auth/callback';

  /// Resuelve la URL absoluta para `emailRedirectTo`.
  /// Visible para tests.
  static String resolve(AuthRedirectType type) {
    return '${currentOrigin()}$callbackPath?type=${type.name}';
  }

  /// `scheme://host[:port]` del navegador actual. En no-web devuelve un
  /// esquema custom (se configurará cuando soportemos móvil/desktop).
  @visibleForTesting
  static String currentOrigin() {
    if (kIsWeb) {
      return Uri.base.origin;
    }
    return 'myapp://';
  }

  /// Sin acceso al navegador — útil para tests que quieren simular un origen
  /// concreto sin depender de `Uri.base`.
  @visibleForTesting
  static String buildRedirect(String origin, AuthRedirectType type) {
    return '$origin$callbackPath?type=${type.name}';
  }
}
