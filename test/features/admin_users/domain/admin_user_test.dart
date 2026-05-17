import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/admin_users/domain/admin_user.dart';

void main() {
  group('AdminUserSummary', () {
    AdminUserSummary parse(Map<String, dynamic> m) =>
        AdminUserSummary.fromMap(m);

    test('parses active row with all fields', () {
      final u = parse(const {
        'id': '11111111-1111-1111-1111-111111111111',
        'email': 'test@example.com',
        'email_confirmed_at': '2026-05-10T10:00:00Z',
        'username': 'tester',
        'display_name': 'Tester',
        'first_name': 'Test',
        'last_name': 'User',
        'avatar_url': 'https://x.com/a.png',
        'locale': 'es',
        'role': 'user',
        'status': 'active',
        'banned_until': null,
        'current_plan_slug': 'pro',
        'current_plan_name': 'Pro',
        'subscription_status': 'active',
        'current_period_end': '2026-06-10T10:00:00Z',
        'signed_up_at': '2026-05-01T10:00:00Z',
        'last_sign_in_at': '2026-05-14T10:00:00Z',
      });
      expect(u.email, 'test@example.com');
      expect(u.isEmailVerified, isTrue);
      expect(u.status, UserStatus.active);
      expect(u.currentPlanName, 'Pro');
      expect(u.isAdmin, isFalse);
      expect(u.bestDisplayName, 'Test User');
    });

    test('bestDisplayName fallback chain', () {
      // first+last → first+last
      expect(
        parse(const {
          'id': '1',
          'email': 'e@e.com',
          'first_name': 'Ana',
          'last_name': 'Lopez',
          'signed_up_at': '2026-05-01T10:00:00Z',
          'status': 'active',
        }).bestDisplayName,
        'Ana Lopez',
      );
      // sin first/last → display_name
      expect(
        parse(const {
          'id': '1',
          'email': 'e@e.com',
          'display_name': 'Pepe',
          'signed_up_at': '2026-05-01T10:00:00Z',
          'status': 'active',
        }).bestDisplayName,
        'Pepe',
      );
      // ni display → username
      expect(
        parse(const {
          'id': '1',
          'email': 'e@e.com',
          'username': 'pepito',
          'signed_up_at': '2026-05-01T10:00:00Z',
          'status': 'active',
        }).bestDisplayName,
        'pepito',
      );
      // nada → email
      expect(
        parse(const {
          'id': '1',
          'email': 'fallback@e.com',
          'signed_up_at': '2026-05-01T10:00:00Z',
          'status': 'active',
        }).bestDisplayName,
        'fallback@e.com',
      );
    });

    test('parses each UserStatus correctly', () {
      expect(
        parse(const {
          'id': '1',
          'email': 'e@e.com',
          'status': 'blocked',
          'signed_up_at': '2026-05-01T10:00:00Z',
        }).status,
        UserStatus.blocked,
      );
      expect(
        parse(const {
          'id': '1',
          'email': 'e@e.com',
          'status': 'deactivated',
          'signed_up_at': '2026-05-01T10:00:00Z',
        }).status,
        UserStatus.deactivated,
      );
      expect(
        parse(const {
          'id': '1',
          'email': 'e@e.com',
          'status': 'unknown',
          'signed_up_at': '2026-05-01T10:00:00Z',
        }).status,
        UserStatus.active,
      );
    });

    test('isEmailVerified false when email_confirmed_at is null', () {
      expect(
        parse(const {
          'id': '1',
          'email': 'e@e.com',
          'status': 'active',
          'signed_up_at': '2026-05-01T10:00:00Z',
        }).isEmailVerified,
        isFalse,
      );
    });

    test('isAdmin true when role = admin', () {
      expect(
        parse(const {
          'id': '1',
          'email': 'e@e.com',
          'role': 'admin',
          'status': 'active',
          'signed_up_at': '2026-05-01T10:00:00Z',
        }).isAdmin,
        isTrue,
      );
    });
  });

  group('AdminUsersKpis', () {
    test('parses full structure', () {
      final k = AdminUsersKpis.fromMap(const {
        'total_users': 120,
        'signups_7d': 8,
        'signups_30d': 25,
        'by_status': {
          'active': 100,
          'blocked': 5,
          'deactivated': 15,
        },
        'by_plan': [
          {'slug': 'free', 'name': 'Free', 'count': 80},
          {'slug': 'pro', 'name': 'Pro', 'count': 40},
        ],
      });
      expect(k.totalUsers, 120);
      expect(k.signups7d, 8);
      expect(k.signups30d, 25);
      expect(k.statusCount(UserStatus.active), 100);
      expect(k.statusCount(UserStatus.blocked), 5);
      expect(k.statusCount(UserStatus.deactivated), 15);
      expect(k.byPlan, hasLength(2));
      expect(k.byPlan.first.slug, 'free');
      expect(k.byPlan.first.count, 80);
    });

    test('handles missing/empty fields with sane defaults', () {
      final k = AdminUsersKpis.fromMap(const {});
      expect(k.totalUsers, 0);
      expect(k.signups7d, 0);
      expect(k.signups30d, 0);
      expect(k.byStatus, isEmpty);
      expect(k.byPlan, isEmpty);
      expect(k.statusCount(UserStatus.active), 0);
    });
  });

  group('AdminUsersListResult', () {
    test('holds rows + total separately', () {
      const r = AdminUsersListResult(
        rows: [],
        totalCount: 42,
      );
      expect(r.rows, isEmpty);
      expect(r.totalCount, 42);
    });
  });

  group('AdminUserDetail', () {
    test('parses with subscription', () {
      final d = AdminUserDetail.fromMap(const {
        'id': '1',
        'email': 'x@x.com',
        'email_confirmed_at': '2026-05-10T10:00:00Z',
        'created_at': '2026-05-01T10:00:00Z',
        'last_sign_in_at': '2026-05-14T10:00:00Z',
        'banned_until': null,
        'status': 'active',
        'profile': {
          'username': 'x',
          'display_name': 'X',
          'role': 'user',
          'locale': 'en',
        },
        'subscription': {
          'plan_slug': 'pro',
          'plan_name': 'Pro',
          'status': 'active',
          'billing_period': 'monthly',
          'current_period_end': '2026-06-10T10:00:00Z',
          'stripe_subscription_id': 'sub_xxx',
        },
        'tenants_count': 2,
        'sessions_count': 3,
        'active_tokens_count': 1,
        'emails_sent_count': 5,
      });
      expect(d.status, UserStatus.active);
      expect(d.subscription?.planName, 'Pro');
      expect(d.subscription?.isPaid, isTrue);
      expect(d.tenantsCount, 2);
      expect(d.sessionsCount, 3);
    });

    test('parses without subscription (free user)', () {
      final d = AdminUserDetail.fromMap(const {
        'id': '1',
        'email': 'x@x.com',
        'created_at': '2026-05-01T10:00:00Z',
        'status': 'active',
        'profile': <String, dynamic>{},
        'subscription': null,
        'tenants_count': 0,
        'sessions_count': 0,
        'active_tokens_count': 0,
        'emails_sent_count': 0,
      });
      expect(d.subscription, isNull);
    });
  });
}
