import 'package:myapp/features/account/domain/entities/profile.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Construye el payload JSON que la app entrega al usuario cuando ejerce su
/// derecho de **portabilidad** (GDPR Art. 20).
///
/// Solo se incluyen datos que ya son del usuario o derivados del estado de
/// su cuenta. NO se exporta:
///   - los hashes de los códigos de recuperación de MFA (no son recuperables
///     ni le sirven al usuario fuera de esta app),
///   - los secretos TOTP de los factores MFA (idem),
///   - claves de OAuth o tokens.
///
/// Estructura versionada con `format: myapp/v1` para poder evolucionar sin
/// romper consumidores externos.
Map<String, dynamic> buildDataExportPayload({
  required User user,
  required Profile? profile,
  required List<MfaFactor> mfaFactors,
  DateTime? now,
}) {
  final exportedAt = (now ?? DateTime.now().toUtc()).toIso8601String();

  // Lista de proveedores con los que el usuario se ha autenticado (email,
  // google, apple…). Sale de `identities` cuando está disponible, y como
  // fallback de `appMetadata.providers` que Supabase rellena.
  final providers = <String>{};
  final identities = user.identities;
  if (identities != null) {
    for (final i in identities) {
      providers.add(i.provider);
    }
  }
  final metaProviders = user.appMetadata['providers'];
  if (metaProviders is List) {
    for (final p in metaProviders) {
      if (p is String) providers.add(p);
    }
  }

  return {
    'exportedAt': exportedAt,
    'format': 'myapp/v1',
    'user': {
      'id': user.id,
      'email': user.email,
      'phone': user.phone,
      'createdAt': user.createdAt,
      'lastSignInAt': user.lastSignInAt,
      'emailConfirmedAt': user.emailConfirmedAt,
      'providers': providers.toList(),
    },
    if (profile != null)
      'profile': {
        'username': profile.username,
        'displayName': profile.displayName,
        'avatarUrl': profile.avatarUrl,
        'locale': profile.locale,
        'themeMode': profile.themeMode,
        'role': profile.role.name,
      },
    'mfa': {
      'factors': [
        for (final f in mfaFactors)
          {
            'id': f.id,
            'type': f.type,
            'status': f.status,
            'friendlyName': f.friendlyName,
          },
      ],
    },
  };
}
