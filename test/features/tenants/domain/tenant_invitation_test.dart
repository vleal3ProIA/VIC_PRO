import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/tenants/domain/tenant_invitation.dart';
import 'package:myapp/features/tenants/domain/tenant_member.dart';

void main() {
  Map<String, Object?> base({
    String? acceptedAt,
    String? revokedAt,
    String? expiresAt,
    String role = 'member',
  }) =>
      <String, Object?>{
        'id': 'inv-1',
        'tenant_id': 't-1',
        'email': 'pal@example.com',
        'role': role,
        'invited_by': 'u-1',
        'expires_at':
            expiresAt ?? DateTime.now().add(const Duration(days: 7)).toIso8601String(),
        'accepted_at': acceptedAt,
        'revoked_at': revokedAt,
        'created_at': '2026-05-15T10:00:00Z',
      };

  group('TenantInvitation.fromMap', () {
    test('parses all fields', () {
      final inv = TenantInvitation.fromMap(base(role: 'admin'));
      expect(inv.id, 'inv-1');
      expect(inv.email, 'pal@example.com');
      expect(inv.role, TenantRole.admin);
      expect(inv.acceptedAt, isNull);
      expect(inv.revokedAt, isNull);
    });

    test('parses accepted_at and revoked_at when present', () {
      final inv = TenantInvitation.fromMap(base(
        acceptedAt: '2026-05-16T10:00:00Z',
        revokedAt: '2026-05-17T11:00:00Z',
      ));
      expect(inv.acceptedAt, isNotNull);
      expect(inv.revokedAt, isNotNull);
    });
  });

  group('isPending', () {
    test('true when not accepted, not revoked, future expiry', () {
      final inv = TenantInvitation.fromMap(base());
      expect(inv.isPending, isTrue);
    });

    test('false when accepted', () {
      final inv = TenantInvitation.fromMap(base(
        acceptedAt: '2026-05-16T10:00:00Z',
      ));
      expect(inv.isPending, isFalse);
    });

    test('false when revoked', () {
      final inv = TenantInvitation.fromMap(base(
        revokedAt: '2026-05-16T10:00:00Z',
      ));
      expect(inv.isPending, isFalse);
    });

    test('false when expired', () {
      final inv = TenantInvitation.fromMap(base(
        expiresAt:
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      ));
      expect(inv.isPending, isFalse);
      expect(inv.isExpired, isTrue);
    });
  });

  test('equality is by id', () {
    final a = TenantInvitation.fromMap(base());
    final b = TenantInvitation.fromMap({...base(), 'email': 'other@x.com'});
    expect(a, equals(b));
  });

  test('CreatedInvitation construction', () {
    final created = CreatedInvitation(
      id: 'abc',
      token: 'secret-token',
      expiresAt: DateTime.parse('2026-05-22T12:00:00Z'),
    );
    expect(created.id, 'abc');
    expect(created.token, 'secret-token');
    expect(created.expiresAt.year, 2026);
  });
}
