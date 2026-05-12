import 'package:flutter/foundation.dart';

enum AuthRedirectType { signup, recovery }

/// URL absoluta a la que Supabase redirige tras el click en un email de auth.
///
/// En web usa `Uri.base` (la URL actual del navegador) para obtener el
/// origen y le añade `/auth/callback?type=...`. El callback page lee ese
/// `type` para distinguir si viene de un signup o de un reset de password.
///
/// IMPORTANTE: el patrón base debe estar listado en
/// **Supabase Dashboard → Authentication → URL Configuration → Redirect URLs**.
class AuthRedirect {
  AuthRedirect._();

  static const String callbackPath = '/auth/callback';

  /// Resuelve la URL absoluta para `emailRedirectTo`.
  static String resolve(AuthRedirectType type) {
    final origin = _origin();
    return '$origin$callbackPath?type=${type.name}';
  }

  static String _origin() {
    if (kIsWeb) {
      final origin = Uri.base.replace(
        path: '',
        query: null,
        fragment: null,
      );
      return origin.toString();
    }
    return 'myapp://';
  }
}
