import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/tenants/domain/tenant.dart';
import 'package:myapp/features/tenants/domain/tenant_member.dart';

void main() {
  group('Tenant.fromMap', () {
    test('parses all fields correctly', () {
      final tenant = Tenant.fromMap({
        'id': 'tenant-1',
        'name': 'Acme',
        'slug': 'acme',
        'owner_id': 'user-1',
        'is_personal': false,
        'created_at': '2026-01-15T10:30:00Z',
      });
      expect(tenant.id, 'tenant-1');
      expect(tenant.name, 'Acme');
      expect(tenant.slug, 'acme');
      expect(tenant.ownerId, 'user-1');
      expect(tenant.isPersonal, isFalse);
      expect(tenant.createdAt.year, 2026);
    });

    test('defaults is_personal to false when missing', () {
      final tenant = Tenant.fromMap({
        'id': 'tenant-1',
        'name': 'X',
        'slug': 'x12',
        'owner_id': 'u',
        'created_at': '2026-01-15T10:30:00Z',
      });
      expect(tenant.isPersonal, isFalse);
    });
  });

  test('Tenant equality is by id', () {
    final t1 = Tenant.fromMap({
      'id': 'same',
      'name': 'A',
      'slug': 'a-1',
      'owner_id': 'u',
      'is_personal': true,
      'created_at': '2026-01-15T10:30:00Z',
    });
    final t2 = Tenant.fromMap({
      'id': 'same',
      'name': 'DIFFERENT',
      'slug': 'b-2',
      'owner_id': 'u',
      'is_personal': false,
      'created_at': '2027-02-20T08:00:00Z',
    });
    expect(t1, equals(t2));
    expect(t1.hashCode, t2.hashCode);
  });

  group('TenantRole', () {
    test('fromString parses known values', () {
      expect(TenantRole.fromString('owner'), TenantRole.owner);
      expect(TenantRole.fromString('admin'), TenantRole.admin);
      expect(TenantRole.fromString('member'), TenantRole.member);
    });

    test('fromString defaults unknown values to member', () {
      expect(TenantRole.fromString('boss'), TenantRole.member);
      expect(TenantRole.fromString(''), TenantRole.member);
    });

    test('isAdmin / isOwner predicates', () {
      expect(TenantRole.owner.isAdmin, isTrue);
      expect(TenantRole.owner.isOwner, isTrue);
      expect(TenantRole.admin.isAdmin, isTrue);
      expect(TenantRole.admin.isOwner, isFalse);
      expect(TenantRole.member.isAdmin, isFalse);
      expect(TenantRole.member.isOwner, isFalse);
    });

    test('toDbString matches Postgres enum value', () {
      expect(TenantRole.owner.toDbString(), 'owner');
      expect(TenantRole.admin.toDbString(), 'admin');
      expect(TenantRole.member.toDbString(), 'member');
    });
  });

  group('TenantMember.fromMap', () {
    test('parses fields', () {
      final m = TenantMember.fromMap({
        'tenant_id': 't1',
        'user_id': 'u1',
        'role': 'admin',
        'joined_at': '2026-01-15T10:30:00Z',
      });
      expect(m.tenantId, 't1');
      expect(m.userId, 'u1');
      expect(m.role, TenantRole.admin);
      expect(m.joinedAt.month, 1);
    });
  });
}
