import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/admin_acl/domain/admin_row.dart';

void main() {
  group('AdminRow.fromMap', () {
    test('parsea todos los campos de una fila completa', () {
      final row = AdminRow.fromMap(const {
        'user_id': '33f6f8c3-4ede-4daf-9ee0-08740169e40d',
        'email': 'vleal3@gmail.com',
        'display_name': 'Victor',
        'is_super_admin': true,
        'capabilities': ['manage_users', 'manage_plans'],
        'created_at': '2026-05-15T07:20:37.867808+00:00',
      });

      expect(row.userId, '33f6f8c3-4ede-4daf-9ee0-08740169e40d');
      expect(row.email, 'vleal3@gmail.com');
      expect(row.displayName, 'Victor');
      expect(row.isSuperAdmin, isTrue);
      expect(row.capabilities, {'manage_users', 'manage_plans'});
      expect(row.createdAt.toUtc().year, 2026);
    });

    test('capabilities ausente o null → set vacío', () {
      final row = AdminRow.fromMap(const {
        'user_id': 'u1',
        'email': 'a@b.com',
        'is_super_admin': false,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(row.capabilities, isEmpty);
      expect(row.isSuperAdmin, isFalse);
    });

    test('capabilities filtra valores no-string', () {
      final row = AdminRow.fromMap(const {
        'user_id': 'u1',
        'email': 'a@b.com',
        'is_super_admin': false,
        'capabilities': ['manage_users', 123, null, 'run_audits'],
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(row.capabilities, {'manage_users', 'run_audits'});
    });

    test('email null → cadena vacía (defensa)', () {
      final row = AdminRow.fromMap(const {
        'user_id': 'u1',
        'email': null,
        'is_super_admin': false,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(row.email, '');
    });
  });

  group('AdminRow.bestDisplayName', () {
    AdminRow make({String? displayName, String email = 'fallback@x.com'}) =>
        AdminRow(
          userId: 'u1',
          email: email,
          displayName: displayName,
          isSuperAdmin: false,
          capabilities: const {},
          createdAt: DateTime.utc(2026),
        );

    test('usa display_name cuando existe y no está vacío', () {
      expect(make(displayName: 'Victor').bestDisplayName, 'Victor');
    });

    test('cae al email cuando display_name es null', () {
      expect(make().bestDisplayName, 'fallback@x.com');
    });

    test('cae al email cuando display_name es vacío o solo espacios', () {
      expect(make(displayName: '   ').bestDisplayName, 'fallback@x.com');
      expect(make(displayName: '').bestDisplayName, 'fallback@x.com');
    });
  });
}
