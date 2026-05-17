import 'package:meta/meta.dart';

/// Estado lógico de un user, derivado de `auth.users.banned_until`:
///   - `active`       → puede entrar
///   - `blocked`      → banned_until > now() pero < año 2099 (temporal)
///   - `deactivated`  → banned_until > año 2099 (perma)
enum UserStatus { active, blocked, deactivated }

UserStatus _parseStatus(String? s) {
  switch (s) {
    case 'blocked':
      return UserStatus.blocked;
    case 'deactivated':
      return UserStatus.deactivated;
    default:
      return UserStatus.active;
  }
}

/// Fila de la tabla `/admin/users`. Compuesta del JOIN auth.users +
/// profiles + sub activa que devuelve `admin_list_users` RPC.
@immutable
class AdminUserSummary {
  const AdminUserSummary({
    required this.id,
    required this.email,
    required this.locale,
    required this.role,
    required this.status,
    required this.currentPlanSlug,
    required this.currentPlanName,
    required this.subscriptionStatus,
    required this.signedUpAt,
    this.emailConfirmedAt,
    this.username,
    this.displayName,
    this.firstName,
    this.lastName,
    this.avatarUrl,
    this.bannedUntil,
    this.currentPeriodEnd,
    this.lastSignInAt,
  });

  factory AdminUserSummary.fromMap(Map<String, dynamic> m) {
    return AdminUserSummary(
      id: m['id'] as String,
      email: m['email'] as String? ?? '',
      emailConfirmedAt: _dt(m['email_confirmed_at']),
      username: m['username'] as String?,
      displayName: m['display_name'] as String?,
      firstName: m['first_name'] as String?,
      lastName: m['last_name'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      locale: m['locale'] as String? ?? 'en',
      role: m['role'] as String? ?? 'user',
      status: _parseStatus(m['status'] as String?),
      bannedUntil: _dt(m['banned_until']),
      currentPlanSlug: m['current_plan_slug'] as String? ?? 'free',
      currentPlanName: m['current_plan_name'] as String? ?? 'Free',
      subscriptionStatus: m['subscription_status'] as String? ?? 'free',
      currentPeriodEnd: _dt(m['current_period_end']),
      signedUpAt: _dt(m['signed_up_at']) ?? DateTime.now(),
      lastSignInAt: _dt(m['last_sign_in_at']),
    );
  }

  final String id;
  final String email;
  final DateTime? emailConfirmedAt;
  final String? username;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? avatarUrl;
  final String locale;
  final String role;
  final UserStatus status;
  final DateTime? bannedUntil;
  final String currentPlanSlug;
  final String currentPlanName;
  final String subscriptionStatus;
  final DateTime? currentPeriodEnd;
  final DateTime signedUpAt;
  final DateTime? lastSignInAt;

  bool get isAdmin => role == 'admin';
  bool get isEmailVerified => emailConfirmedAt != null;

  String get bestDisplayName {
    final fl = [firstName, lastName].whereType<String>().join(' ').trim();
    if (fl.isNotEmpty) return fl;
    if (displayName?.isNotEmpty ?? false) return displayName!;
    if (username?.isNotEmpty ?? false) return username!;
    return email;
  }
}

/// Detalle completo de un user para `/admin/users/<id>`. JSON anidado
/// que devuelve `admin_get_user_detail` RPC.
@immutable
class AdminUserDetail {
  const AdminUserDetail({
    required this.id,
    required this.email,
    required this.status,
    required this.profile,
    required this.tenantsCount,
    required this.sessionsCount,
    required this.activeTokensCount,
    required this.emailsSentCount,
    required this.createdAt,
    this.emailConfirmedAt,
    this.phone,
    this.lastSignInAt,
    this.bannedUntil,
    this.subscription,
  });

  factory AdminUserDetail.fromMap(Map<String, dynamic> m) {
    return AdminUserDetail(
      id: m['id'] as String,
      email: m['email'] as String? ?? '',
      emailConfirmedAt: _dt(m['email_confirmed_at']),
      phone: m['phone'] as String?,
      createdAt: _dt(m['created_at']) ?? DateTime.now(),
      lastSignInAt: _dt(m['last_sign_in_at']),
      bannedUntil: _dt(m['banned_until']),
      status: _parseStatus(m['status'] as String?),
      profile: AdminUserProfile.fromMap(
        (m['profile'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      subscription: m['subscription'] != null
          ? AdminUserSubscription.fromMap(
              (m['subscription'] as Map).cast<String, dynamic>(),
            )
          : null,
      tenantsCount: (m['tenants_count'] as num?)?.toInt() ?? 0,
      sessionsCount: (m['sessions_count'] as num?)?.toInt() ?? 0,
      activeTokensCount: (m['active_tokens_count'] as num?)?.toInt() ?? 0,
      emailsSentCount: (m['emails_sent_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String email;
  final DateTime? emailConfirmedAt;
  final String? phone;
  final DateTime createdAt;
  final DateTime? lastSignInAt;
  final DateTime? bannedUntil;
  final UserStatus status;
  final AdminUserProfile profile;
  final AdminUserSubscription? subscription;
  final int tenantsCount;
  final int sessionsCount;
  final int activeTokensCount;
  final int emailsSentCount;
}

@immutable
class AdminUserProfile {
  const AdminUserProfile({
    this.username,
    this.displayName,
    this.firstName,
    this.lastName,
    this.avatarUrl,
    this.locale = 'en',
    this.themeMode = 'system',
    this.role = 'user',
    this.country,
    this.city,
  });

  factory AdminUserProfile.fromMap(Map<String, dynamic> m) => AdminUserProfile(
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        firstName: m['first_name'] as String?,
        lastName: m['last_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        locale: m['locale'] as String? ?? 'en',
        themeMode: m['theme_mode'] as String? ?? 'system',
        role: m['role'] as String? ?? 'user',
        country: m['country'] as String?,
        city: m['city'] as String?,
      );

  final String? username;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? avatarUrl;
  final String locale;
  final String themeMode;
  final String role;
  final String? country;
  final String? city;
}

@immutable
class AdminUserSubscription {
  const AdminUserSubscription({
    required this.planSlug,
    required this.planName,
    required this.status,
    required this.billingPeriod,
    this.id,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.canceledAt,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
  });

  factory AdminUserSubscription.fromMap(Map<String, dynamic> m) =>
      AdminUserSubscription(
        id: m['id'] as String?,
        planSlug: m['plan_slug'] as String? ?? 'free',
        planName: m['plan_name'] as String? ?? 'Free',
        status: m['status'] as String? ?? 'free',
        billingPeriod: m['billing_period'] as String? ?? 'monthly',
        currentPeriodStart: _dt(m['current_period_start']),
        currentPeriodEnd: _dt(m['current_period_end']),
        cancelAtPeriodEnd: m['cancel_at_period_end'] as bool? ?? false,
        canceledAt: _dt(m['canceled_at']),
        stripeCustomerId: m['stripe_customer_id'] as String?,
        stripeSubscriptionId: m['stripe_subscription_id'] as String?,
      );

  final String? id;
  final String planSlug;
  final String planName;
  final String status;
  final String billingPeriod;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final DateTime? canceledAt;
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;

  bool get isPaid =>
      stripeSubscriptionId != null && stripeSubscriptionId!.isNotEmpty;
}

/// KPIs del header `/admin/users`. Estructura del JSON que devuelve
/// `admin_users_kpis` RPC.
@immutable
class AdminUsersKpis {
  const AdminUsersKpis({
    required this.totalUsers,
    required this.signups7d,
    required this.signups30d,
    required this.byStatus,
    required this.byPlan,
  });

  factory AdminUsersKpis.fromMap(Map<String, dynamic> m) {
    final byStatusRaw = (m['by_status'] as Map?)?.cast<String, dynamic>()
        ?? const {};
    final byPlanRaw = (m['by_plan'] as List?)
            ?.cast<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    return AdminUsersKpis(
      totalUsers: (m['total_users'] as num?)?.toInt() ?? 0,
      signups7d: (m['signups_7d'] as num?)?.toInt() ?? 0,
      signups30d: (m['signups_30d'] as num?)?.toInt() ?? 0,
      byStatus: byStatusRaw.map(
        (k, v) => MapEntry(_parseStatus(k), (v as num).toInt()),
      ),
      byPlan: byPlanRaw
          .map(
            (m) => PlanCount(
              slug: m['slug'] as String,
              name: m['name'] as String,
              count: (m['count'] as num).toInt(),
            ),
          )
          .toList(growable: false),
    );
  }

  final int totalUsers;
  final int signups7d;
  final int signups30d;
  final Map<UserStatus, int> byStatus;
  final List<PlanCount> byPlan;

  int statusCount(UserStatus s) => byStatus[s] ?? 0;
}

@immutable
class PlanCount {
  const PlanCount({
    required this.slug,
    required this.name,
    required this.count,
  });
  final String slug;
  final String name;
  final int count;
}

/// Resultado de `admin_list_users` con el total (para paginar) y los
/// rows. Si `rows` está vacía, `totalCount` también lo está; en otro
/// caso `totalCount` viene replicado en cada row y lo leemos del primero.
@immutable
class AdminUsersListResult {
  const AdminUsersListResult({required this.rows, required this.totalCount});
  final List<AdminUserSummary> rows;
  final int totalCount;
}

DateTime? _dt(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}
