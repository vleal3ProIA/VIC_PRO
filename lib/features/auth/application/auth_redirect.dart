import 'package:flutter/foundation.dart';

/// URL absoluta a la que Supabase redirige tras el click en el email de
/// verificación. En web, el navegador actual nos da el origen
/// (`http://localhost:5000` en dev, dominio en prod).
///
/// IMPORTANTE: esta URL debe estar listada en
/// **Supabase Dashboard → Authentication → URL Configuration → Redirect URLs**.
class AuthRedirect {
  AuthRedirect._();

  static const String callbackPath = '/auth/callback';

  /// Origen + path de callback. En web siempre devuelve algo correcto.
  static String resolve() {
    if (kIsWeb) {
      // En web usamos Uri.base, que en runtime es la URL actual del navegador.
      final origin = Uri.base.replace(
        path: '',
        query: null,
        fragment: null,
      );
      return '$origin$callbackPath';
    }
    // En móvil/desktop usaríamos un deep link custom (lo configuramos
    // cuando saquemos esas plataformas).
    return 'myapp://auth/callback';
  }
}
