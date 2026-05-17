import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/tokens/domain/personal_access_token.dart';

void main() {
  group('PersonalAccessToken.fromMap', () {
    test('parses an active token with all optional fields', () {
      final t = PersonalAccessToken.fromMap(const {
        'id': '11111111-1111-1111-1111-111111111111',
        'name': 'CI deploy',
        'prefix': 'pat_a1b2c3d4',
        'scopes': ['read', 'write'],
        'created_at': '2026-05-01T10:00:00Z',
        'expires_at': '2026-08-01T10:00:00Z',
        'last_used_at': '2026-05-10T15:30:00Z',
        'revoked_at': null,
      });
      expect(t.name, 'CI deploy');
      expect(t.prefix, 'pat_a1b2c3d4');
      expect(t.scopes, ['read', 'write']);
      expect(t.expiresAt!.month, 8);
      expect(t.lastUsedAt, isNotNull);
      expect(t.revokedAt, isNull);
      expect(t.secret, isNull);
    });

    test('defaults scopes to [read] when missing', () {
      final t = PersonalAccessToken.fromMap(const {
        'id': '1',
        'name': 'x',
        'prefix': 'pat_zzzzzzzz',
        'created_at': '2026-05-01T10:00:00Z',
      });
      expect(t.scopes, ['read']);
      expect(t.canWrite, isFalse);
    });

    test('parses raw secret from create response', () {
      final t = PersonalAccessToken.fromMap(const {
        'id': '1',
        'name': 'x',
        'prefix': 'pat_zzzzzzzz',
        'scopes': ['read'],
        'created_at': '2026-05-01T10:00:00Z',
        'token': 'pat_zzzzzzzz_supersecret',
      });
      expect(t.secret, 'pat_zzzzzzzz_supersecret');
    });
  });

  group('state flags', () {
    test('isActive when no revoke and no expiration', () {
      final t = PersonalAccessToken.fromMap(const {
        'id': '1',
        'name': 'x',
        'prefix': 'pat_a1b2c3d4',
        'created_at': '2026-05-01T10:00:00Z',
      });
      expect(t.isActive, isTrue);
      expect(t.isRevoked, isFalse);
      expect(t.isExpired, isFalse);
    });

    test('isRevoked when revoked_at present', () {
      final t = PersonalAccessToken.fromMap(const {
        'id': '1',
        'name': 'x',
        'prefix': 'pat_a1b2c3d4',
        'created_at': '2026-05-01T10:00:00Z',
        'revoked_at': '2026-05-05T10:00:00Z',
      });
      expect(t.isRevoked, isTrue);
      expect(t.isActive, isFalse);
    });

    test('isExpired when expires_at in the past', () {
      final past =
          DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
      final t = PersonalAccessToken.fromMap({
        'id': '1',
        'name': 'x',
        'prefix': 'pat_a1b2c3d4',
        'created_at': '2026-05-01T10:00:00Z',
        'expires_at': past,
      });
      expect(t.isExpired, isTrue);
      expect(t.isActive, isFalse);
    });

    test('not expired when expires_at in the future', () {
      final future =
          DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String();
      final t = PersonalAccessToken.fromMap({
        'id': '1',
        'name': 'x',
        'prefix': 'pat_a1b2c3d4',
        'created_at': '2026-05-01T10:00:00Z',
        'expires_at': future,
      });
      expect(t.isExpired, isFalse);
      expect(t.isActive, isTrue);
    });
  });

  group('canWrite', () {
    test('true when scopes contain write', () {
      final t = PersonalAccessToken.fromMap(const {
        'id': '1',
        'name': 'x',
        'prefix': 'pat_a1b2c3d4',
        'scopes': ['read', 'write'],
        'created_at': '2026-05-01T10:00:00Z',
      });
      expect(t.canWrite, isTrue);
    });

    test('false when only read', () {
      final t = PersonalAccessToken.fromMap(const {
        'id': '1',
        'name': 'x',
        'prefix': 'pat_a1b2c3d4',
        'scopes': ['read'],
        'created_at': '2026-05-01T10:00:00Z',
      });
      expect(t.canWrite, isFalse);
    });
  });
}
