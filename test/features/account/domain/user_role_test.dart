import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/account/domain/entities/profile.dart';
import 'package:myapp/features/account/domain/entities/user_role.dart';

void main() {
  group('UserRole.fromString', () {
    test('maps known values', () {
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('user'), UserRole.user);
      expect(UserRole.fromString('guest'), UserRole.guest);
    });

    test('unknown or null falls back to user', () {
      expect(UserRole.fromString(null), UserRole.user);
      expect(UserRole.fromString('superadmin'), UserRole.user);
      expect(UserRole.fromString(''), UserRole.user);
    });
  });

  group('UserRole flags', () {
    test('isAdmin only for admin', () {
      expect(UserRole.admin.isAdmin, isTrue);
      expect(UserRole.user.isAdmin, isFalse);
      expect(UserRole.guest.isAdmin, isFalse);
    });

    test('isAuthenticated true except guest', () {
      expect(UserRole.admin.isAuthenticated, isTrue);
      expect(UserRole.user.isAuthenticated, isTrue);
      expect(UserRole.guest.isAuthenticated, isFalse);
    });

    test('dbValue never serialises guest', () {
      expect(UserRole.admin.dbValue, 'admin');
      expect(UserRole.user.dbValue, 'user');
      expect(UserRole.guest.dbValue, 'user');
    });
  });

  group('Profile.fromMap role', () {
    test('reads role from the map', () {
      final p = Profile.fromMap({
        'id': 'u1',
        'role': 'admin',
        'locale': 'en',
        'theme_mode': 'system',
      });
      expect(p.role, UserRole.admin);
    });

    test('defaults to user when role missing', () {
      final p = Profile.fromMap({
        'id': 'u1',
        'locale': 'en',
        'theme_mode': 'system',
      });
      expect(p.role, UserRole.user);
    });
  });
}
