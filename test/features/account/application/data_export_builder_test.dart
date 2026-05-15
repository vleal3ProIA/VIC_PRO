import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/account/application/data_export_builder.dart';
import 'package:myapp/features/account/domain/entities/profile.dart';
import 'package:myapp/features/account/domain/entities/user_role.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  User userFromMap(Map<String, dynamic> overrides) {
    return User.fromJson({
      'id': 'user-1',
      'aud': 'authenticated',
      'created_at': '2026-01-15T10:00:00Z',
      'app_metadata': const <String, dynamic>{},
      'user_metadata': const <String, dynamic>{},
      'email': 'me@example.com',
      ...overrides,
    })!;
  }

  group('buildDataExportPayload', () {
    test('shape: top-level keys + format version', () {
      final payload = buildDataExportPayload(
        user: userFromMap(const {}),
        profile: null,
        mfaFactors: const [],
        now: DateTime.utc(2026, 5, 15, 18, 30),
      );
      expect(payload['format'], 'myapp/v1');
      expect(payload['exportedAt'], '2026-05-15T18:30:00.000Z');
      expect(payload['user'], isA<Map<String, dynamic>>());
      expect(payload['mfa'], isA<Map<String, dynamic>>());
      expect(payload.containsKey('profile'), isFalse); // null → omitted
    });

    test('user block carries id, email, dates', () {
      final payload = buildDataExportPayload(
        user: userFromMap({
          'email': 'vic@example.com',
          'created_at': '2026-01-15T10:00:00Z',
          'email_confirmed_at': '2026-01-15T10:05:00Z',
          'last_sign_in_at': '2026-05-15T18:00:00Z',
        }),
        profile: null,
        mfaFactors: const [],
      );
      final user = payload['user'] as Map<String, dynamic>;
      expect(user['id'], 'user-1');
      expect(user['email'], 'vic@example.com');
      expect(user['createdAt'], '2026-01-15T10:00:00Z');
      expect(user['emailConfirmedAt'], '2026-01-15T10:05:00Z');
      expect(user['lastSignInAt'], '2026-05-15T18:00:00Z');
    });

    test('profile block includes role and preferences when present', () {
      final payload = buildDataExportPayload(
        user: userFromMap(const {}),
        profile: const Profile(
          id: 'user-1',
          username: 'victor',
          displayName: 'Víctor',
          avatarUrl: 'https://example.com/a.png?v=1',
          locale: 'es',
          themeMode: 'dark',
          role: UserRole.admin,
        ),
        mfaFactors: const [],
      );
      final profile = payload['profile'] as Map<String, dynamic>;
      expect(profile['username'], 'victor');
      expect(profile['displayName'], 'Víctor');
      expect(profile['avatarUrl'], 'https://example.com/a.png?v=1');
      expect(profile['locale'], 'es');
      expect(profile['themeMode'], 'dark');
      expect(profile['role'], 'admin');
    });

    test('mfa factors include only safe fields (id/type/status/name)', () {
      final payload = buildDataExportPayload(
        user: userFromMap(const {}),
        profile: null,
        mfaFactors: const [
          MfaFactor(
            id: 'f1',
            type: 'totp',
            status: 'verified',
            friendlyName: 'myapp',
          ),
        ],
      );
      final factors = (payload['mfa'] as Map<String, dynamic>)['factors']
          as List<dynamic>;
      expect(factors, hasLength(1));
      final f = factors.first as Map<String, dynamic>;
      expect(f['id'], 'f1');
      expect(f['type'], 'totp');
      expect(f['status'], 'verified');
      expect(f['friendlyName'], 'myapp');
      // Asegura que NO se cuela ningún campo sensible — la clave del payload
      // pasa la auditoría: sin secretos TOTP ni hashes de recovery codes.
      expect(f.keys.toSet(), {'id', 'type', 'status', 'friendlyName'});
    });

    test('providers: unique union of identities + appMetadata.providers', () {
      final payload = buildDataExportPayload(
        user: userFromMap({
          'app_metadata': const {
            'providers': ['email', 'google'],
          },
          'identities': [
            {
              'id': 'i1',
              'user_id': 'user-1',
              'identity_id': 'i1',
              'provider': 'google',
              'identity_data': <String, dynamic>{},
              'created_at': '2026-01-15T10:00:00Z',
              'updated_at': '2026-01-15T10:00:00Z',
              'last_sign_in_at': '2026-01-15T10:00:00Z',
            },
          ],
        }),
        profile: null,
        mfaFactors: const [],
      );
      final providers =
          ((payload['user'] as Map)['providers'] as List).cast<String>();
      expect(providers.toSet(), {'email', 'google'}); // deduplicado
    });
  });
}
