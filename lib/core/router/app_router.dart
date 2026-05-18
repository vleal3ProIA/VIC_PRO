import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/router/router_guards.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/presentation/pages/account_sessions_page.dart';
import 'package:myapp/features/account/presentation/pages/account_settings_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_trash_page.dart';
import 'package:myapp/features/admin_metrics/presentation/pages/admin_metrics_page.dart';
import 'package:myapp/features/admin_users/presentation/pages/admin_user_detail_page.dart';
import 'package:myapp/features/admin_users/presentation/pages/admin_users_page.dart';
import 'package:myapp/features/audit/presentation/pages/activity_feed_page.dart';
import 'package:myapp/features/audit/presentation/pages/audit_log_page.dart';
import 'package:myapp/features/auth/application/mfa_providers.dart';
import 'package:myapp/features/auth/presentation/pages/auth_callback_page.dart';
import 'package:myapp/features/auth/presentation/pages/change_email_page.dart';
import 'package:myapp/features/auth/presentation/pages/change_email_sent_page.dart';
import 'package:myapp/features/auth/presentation/pages/change_password_done_page.dart';
import 'package:myapp/features/auth/presentation/pages/change_password_page.dart';
import 'package:myapp/features/auth/presentation/pages/delete_account_page.dart';
import 'package:myapp/features/auth/presentation/pages/email_changed_page.dart';
import 'package:myapp/features/auth/presentation/pages/email_verified_page.dart';
import 'package:myapp/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:myapp/features/auth/presentation/pages/login_page.dart';
import 'package:myapp/features/auth/presentation/pages/magic_link_page.dart';
import 'package:myapp/features/auth/presentation/pages/magic_link_sent_page.dart';
import 'package:myapp/features/auth/presentation/pages/mfa_challenge_page.dart';
import 'package:myapp/features/auth/presentation/pages/mfa_setup_page.dart';
import 'package:myapp/features/auth/presentation/pages/otp_request_page.dart';
import 'package:myapp/features/auth/presentation/pages/otp_verify_page.dart';
import 'package:myapp/features/auth/presentation/pages/passkeys_page.dart';
import 'package:myapp/features/auth/presentation/pages/password_reset_sent_page.dart';
import 'package:myapp/features/auth/presentation/pages/password_updated_page.dart';
import 'package:myapp/features/auth/presentation/pages/register_page.dart';
import 'package:myapp/features/auth/presentation/pages/set_new_password_page.dart';
import 'package:myapp/features/auth/presentation/pages/verify_email_sent_page.dart';
import 'package:myapp/features/billing/presentation/pages/admin_branding_page.dart';
import 'package:myapp/features/billing/presentation/pages/admin_coupons_page.dart';
import 'package:myapp/features/billing/presentation/pages/admin_plans_page.dart';
import 'package:myapp/features/billing/presentation/pages/billing_info_page.dart';
import 'package:myapp/features/billing/presentation/pages/billing_success_page.dart';
import 'package:myapp/features/billing/presentation/pages/embedded_checkout_page.dart';
import 'package:myapp/features/billing/presentation/pages/invoices_page.dart';
import 'package:myapp/features/billing/presentation/pages/plans_page.dart';
import 'package:myapp/features/branding/application/branding_providers.dart';
import 'package:myapp/features/branding/presentation/pages/admin_app_branding_page.dart';
import 'package:myapp/features/branding/presentation/pages/setup_page.dart';
import 'package:myapp/features/broadcasts/presentation/pages/admin_broadcast_detail_page.dart';
import 'package:myapp/features/broadcasts/presentation/pages/admin_broadcast_new_page.dart';
import 'package:myapp/features/broadcasts/presentation/pages/admin_broadcasts_page.dart';
import 'package:myapp/features/emails/presentation/pages/admin_email_log_page.dart';
import 'package:myapp/features/flags/presentation/pages/admin_flags_page.dart';
import 'package:myapp/features/help/presentation/pages/admin_changelog_page.dart';
import 'package:myapp/features/help/presentation/pages/changelog_page.dart';
import 'package:myapp/features/home/presentation/pages/home_page.dart';
import 'package:myapp/features/legal/presentation/pages/cookies_page.dart';
import 'package:myapp/features/legal/presentation/pages/privacy_page.dart';
import 'package:myapp/features/legal/presentation/pages/terms_page.dart';
import 'package:myapp/features/notifications/presentation/pages/notifications_page.dart';
import 'package:myapp/features/onboarding/application/onboarding_providers.dart';
import 'package:myapp/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:myapp/features/shell/presentation/widgets/private_shell.dart';
import 'package:myapp/features/status/presentation/pages/admin_incidents_page.dart';
import 'package:myapp/features/status/presentation/pages/status_page.dart';
import 'package:myapp/features/tenants/presentation/pages/accept_invite_page.dart';
import 'package:myapp/features/tenants/presentation/pages/team_page.dart';
import 'package:myapp/features/tokens/presentation/pages/tokens_page.dart';
import 'package:myapp/features/uploads/presentation/pages/files_page.dart';
import 'package:myapp/features/webhooks/presentation/pages/webhook_detail_page.dart';
import 'package:myapp/features/webhooks/presentation/pages/webhooks_page.dart';
import 'package:myapp/features/welcome/presentation/pages/welcome_page.dart';

/// `true` si hay sesion activa del lado del SDK de Supabase. Lo lee
/// el guard del router para decidir si dejar pasar a rutas privadas.
///
/// En produccion lee directo del getter `currentSession` (no del stream
/// `onAuthStateChange`) porque ese stream entrega los eventos de forma
/// asincrona y justo tras `signIn` podria estar "stale" durante un tick.
/// El getter `currentSession` siempre esta fresco.
///
/// Existe como provider separado para que los tests E2E del router
/// puedan overridearlo con `true` / `false` sin tener que construir un
/// `Session` real ni inicializar el cliente Supabase. Ver
/// `test/core/router/app_router_guards_test.dart`.
final routerIsAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(supabaseClientProvider).auth.currentSession != null;
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: RoutePaths.welcome,
    debugLogDiagnostics: true,
    refreshListenable: refreshNotifier,
    redirect: (context, state) => appRouterRedirect(ref, state),
    routes: [
      GoRoute(
        path: RoutePaths.welcome,
        name: RouteNames.welcome,
        builder: (_, __) => const WelcomePage(),
      ),
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: RoutePaths.register,
        name: RouteNames.register,
        builder: (_, __) => const RegisterPage(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        name: RouteNames.forgotPassword,
        builder: (_, __) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: RoutePaths.passwordResetSent,
        name: RouteNames.passwordResetSent,
        builder: (_, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return PasswordResetSentPage(email: email);
        },
      ),
      GoRoute(
        path: RoutePaths.setNewPassword,
        name: RouteNames.setNewPassword,
        builder: (_, __) => const SetNewPasswordPage(),
      ),
      GoRoute(
        path: RoutePaths.passwordUpdated,
        name: RouteNames.passwordUpdated,
        builder: (_, __) => const PasswordUpdatedPage(),
      ),
      GoRoute(
        path: RoutePaths.verifyEmailSent,
        name: RouteNames.verifyEmailSent,
        builder: (_, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return VerifyEmailSentPage(email: email);
        },
      ),
      GoRoute(
        path: RoutePaths.emailVerified,
        name: RouteNames.emailVerified,
        builder: (_, __) => const EmailVerifiedPage(),
      ),
      GoRoute(
        path: RoutePaths.authCallback,
        name: RouteNames.authCallback,
        builder: (_, __) => const AuthCallbackPage(),
      ),
      GoRoute(
        path: RoutePaths.magicLink,
        name: RouteNames.magicLink,
        builder: (_, __) => const MagicLinkPage(),
      ),
      GoRoute(
        path: RoutePaths.magicLinkSent,
        name: RouteNames.magicLinkSent,
        builder: (_, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return MagicLinkSentPage(email: email);
        },
      ),
      GoRoute(
        path: RoutePaths.otpRequest,
        name: RouteNames.otpRequest,
        builder: (_, __) => const OtpRequestPage(),
      ),
      GoRoute(
        path: RoutePaths.otpVerify,
        name: RouteNames.otpVerify,
        builder: (_, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return OtpVerifyPage(email: email);
        },
      ),
      GoRoute(
        path: RoutePaths.mfaSetup,
        name: RouteNames.mfaSetup,
        builder: (_, __) => const MfaSetupPage(),
      ),
      GoRoute(
        path: RoutePaths.mfaChallenge,
        name: RouteNames.mfaChallenge,
        builder: (_, __) => const MfaChallengePage(),
      ),
      // Zona privada con shell persistente (cabecera + navegación lateral).
      // Solo envuelve los destinos "de navegación"; los flujos puntuales
      // (cambio de password/email, borrado, MFA) van fuera, a pantalla
      // completa.
      ShellRoute(
        builder: (context, state, child) => PrivateShell(
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: RoutePaths.home,
            name: RouteNames.home,
            builder: (_, __) => const HomePage(),
          ),
          GoRoute(
            path: RoutePaths.accountSettings,
            name: RouteNames.accountSettings,
            builder: (_, __) => const AccountSettingsPage(),
          ),
          GoRoute(
            path: RoutePaths.admin,
            name: RouteNames.admin,
            builder: (_, __) => const AdminPage(),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.changePassword,
        name: RouteNames.changePassword,
        builder: (_, __) => const ChangePasswordPage(),
      ),
      GoRoute(
        path: RoutePaths.changePasswordDone,
        name: RouteNames.changePasswordDone,
        builder: (_, __) => const ChangePasswordDonePage(),
      ),
      GoRoute(
        path: RoutePaths.changeEmail,
        name: RouteNames.changeEmail,
        builder: (_, __) => const ChangeEmailPage(),
      ),
      GoRoute(
        path: RoutePaths.changeEmailSent,
        name: RouteNames.changeEmailSent,
        builder: (_, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return ChangeEmailSentPage(email: email);
        },
      ),
      GoRoute(
        path: RoutePaths.emailChanged,
        name: RouteNames.emailChanged,
        builder: (_, __) => const EmailChangedPage(),
      ),
      GoRoute(
        path: RoutePaths.deleteAccount,
        name: RouteNames.deleteAccount,
        builder: (_, __) => const DeleteAccountPage(),
      ),
      GoRoute(
        path: RoutePaths.passkeys,
        name: RouteNames.passkeys,
        builder: (_, __) => const PasskeysPage(),
      ),
      GoRoute(
        path: RoutePaths.sessions,
        name: RouteNames.sessions,
        builder: (_, __) => const AccountSessionsPage(),
      ),
      GoRoute(
        path: RoutePaths.files,
        name: RouteNames.files,
        builder: (_, __) => const FilesPage(),
      ),
      GoRoute(
        path: RoutePaths.tokens,
        name: RouteNames.tokens,
        builder: (_, __) => const TokensPage(),
      ),
      GoRoute(
        path: RoutePaths.webhooks,
        name: RouteNames.webhooks,
        builder: (_, __) => const WebhooksPage(),
      ),
      GoRoute(
        path: RoutePaths.webhookDetail,
        name: RouteNames.webhookDetail,
        builder: (_, state) => WebhookDetailPage(
          endpointId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        name: RouteNames.notifications,
        builder: (_, __) => const NotificationsPage(),
      ),
      GoRoute(
        path: RoutePaths.onboarding,
        name: RouteNames.onboarding,
        builder: (_, __) => const OnboardingPage(),
      ),
      GoRoute(
        path: RoutePaths.auditLog,
        name: RouteNames.auditLog,
        builder: (_, __) => const AuditLogPage(),
      ),
      GoRoute(
        path: RoutePaths.activity,
        name: RouteNames.activity,
        builder: (_, __) => const ActivityFeedPage(),
      ),
      GoRoute(
        path: RoutePaths.team,
        name: RouteNames.team,
        builder: (_, __) => const TeamPage(),
      ),
      GoRoute(
        path: RoutePaths.adminFlags,
        name: RouteNames.adminFlags,
        builder: (_, __) => const AdminFlagsPage(),
      ),
      GoRoute(
        path: RoutePaths.adminPlans,
        name: RouteNames.adminPlans,
        builder: (_, __) => const AdminPlansPage(),
      ),
      GoRoute(
        path: RoutePaths.adminBranding,
        name: RouteNames.adminBranding,
        builder: (_, __) => const AdminBrandingPage(),
      ),
      GoRoute(
        path: RoutePaths.adminCoupons,
        name: RouteNames.adminCoupons,
        builder: (_, __) => const AdminCouponsPage(),
      ),
      GoRoute(
        path: RoutePaths.adminTrash,
        name: RouteNames.adminTrash,
        builder: (_, __) => const AdminTrashPage(),
      ),
      GoRoute(
        path: RoutePaths.adminChangelog,
        name: RouteNames.adminChangelog,
        builder: (_, __) => const AdminChangelogPage(),
      ),
      GoRoute(
        path: RoutePaths.changelog,
        name: RouteNames.changelog,
        builder: (_, __) => const ChangelogPage(),
      ),
      GoRoute(
        path: RoutePaths.adminAppBranding,
        name: RouteNames.adminAppBranding,
        builder: (_, __) => const AdminAppBrandingPage(),
      ),
      GoRoute(
        path: RoutePaths.setup,
        name: RouteNames.setup,
        builder: (_, __) => const SetupPage(),
      ),
      GoRoute(
        path: RoutePaths.adminEmailLog,
        name: RouteNames.adminEmailLog,
        builder: (_, __) => const AdminEmailLogPage(),
      ),
      GoRoute(
        path: RoutePaths.adminUsers,
        name: RouteNames.adminUsers,
        builder: (_, __) => const AdminUsersPage(),
      ),
      GoRoute(
        path: RoutePaths.adminUserDetail,
        name: RouteNames.adminUserDetail,
        builder: (_, state) => AdminUserDetailPage(
          userId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: RoutePaths.adminMetrics,
        name: RouteNames.adminMetrics,
        builder: (_, __) => const AdminMetricsPage(),
      ),
      GoRoute(
        path: RoutePaths.adminBroadcasts,
        name: RouteNames.adminBroadcasts,
        builder: (_, __) => const AdminBroadcastsPage(),
      ),
      // /new debe ir antes que /:id; GoRouter prueba en orden y :id
      // matchearia con 'new' lo cual romperia.
      GoRoute(
        path: RoutePaths.adminBroadcastsNew,
        name: RouteNames.adminBroadcastsNew,
        builder: (_, __) => const AdminBroadcastNewPage(),
      ),
      GoRoute(
        path: RoutePaths.adminBroadcastDetail,
        name: RouteNames.adminBroadcastDetail,
        builder: (_, state) => AdminBroadcastDetailPage(
          broadcastId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: RoutePaths.adminIncidents,
        name: RouteNames.adminIncidents,
        builder: (_, __) => const AdminIncidentsPage(),
      ),
      GoRoute(
        path: RoutePaths.status,
        name: RouteNames.status,
        builder: (_, __) => const StatusPage(),
      ),
      GoRoute(
        path: RoutePaths.plans,
        name: RouteNames.plans,
        builder: (_, __) => const PlansPage(),
      ),
      GoRoute(
        path: RoutePaths.billingSuccess,
        name: RouteNames.billingSuccess,
        builder: (_, state) => BillingSuccessPage(
          sessionId: state.uri.queryParameters['session_id'],
        ),
      ),
      GoRoute(
        path: RoutePaths.billingInfo,
        name: RouteNames.billingInfo,
        builder: (_, state) => BillingInfoPage(
          returnTo: state.uri.queryParameters['return'],
        ),
      ),
      GoRoute(
        path: RoutePaths.embeddedCheckout,
        name: RouteNames.embeddedCheckout,
        builder: (_, state) => EmbeddedCheckoutPage(
          planSlug: state.uri.queryParameters['plan_slug'] ?? '',
          billingPeriod:
              state.uri.queryParameters['billing_period'] ?? 'monthly',
          stripePromotionCodeId:
              state.uri.queryParameters['stripe_promotion_code_id'],
        ),
      ),
      GoRoute(
        path: RoutePaths.invoices,
        name: RouteNames.invoices,
        builder: (_, __) => const InvoicesPage(),
      ),
      GoRoute(
        path: RoutePaths.acceptInvite,
        name: RouteNames.acceptInvite,
        builder: (_, state) => AcceptInvitePage(
          token: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: RoutePaths.terms,
        name: RouteNames.terms,
        builder: (_, __) => const TermsPage(),
      ),
      GoRoute(
        path: RoutePaths.privacy,
        name: RouteNames.privacy,
        builder: (_, __) => const PrivacyPage(),
      ),
      GoRoute(
        path: RoutePaths.cookies,
        name: RouteNames.cookies,
        builder: (_, __) => const CookiesPage(),
      ),
    ],
    errorBuilder: (_, state) => _NotFoundPage(error: state.error),
  );
});

/// Wrapper que lee los providers necesarios desde Riverpod y delega a
/// `evaluateRouterRedirect` (funcion pura definida en
/// `lib/core/router/router_guards.dart`). Es el callback que pasamos a
/// `GoRouter.redirect` en produccion.
///
/// La logica del guard vive en `router_guards.dart` para que los tests
/// la puedan importar sin arrastrar dependencias web-only (webauthn_js,
/// stripe_js) que `app_router.dart` trae via las pages.
String? appRouterRedirect(Ref ref, GoRouterState state) {
  return evaluateRouterRedirect(
    matchedLocation: state.matchedLocation,
    isAuthenticated: ref.read(routerIsAuthenticatedProvider),
    branding: ref.read(appBrandingProvider).valueOrNull,
    mfaPending: ref.read(mfaChallengePendingProvider),
    isAdmin: ref.read(isAdminProvider),
    onboardingCompleted: ref.read(onboardingCompletedProvider).valueOrNull,
  );
}

/// Adaptador entre el `StreamProvider<AuthState>` y el `Listenable` que
/// `GoRouter.refreshListenable` espera. Cada vez que cambia el estado de
/// auth, notificamos para que el router re-evalúe `redirect`.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(this._ref) {
    _authSub = _ref.listen(
      authStateChangesProvider,
      (_, __) => notifyListeners(),
    );
    // El rol llega de forma asíncrona (al cargar el perfil). Re-evaluamos
    // el redirect cuando cambia, para que el guard de rutas solo-admin no
    // se quede con un rol "stale".
    _roleSub = _ref.listen(
      currentRoleProvider,
      (_, __) => notifyListeners(),
    );
    // El branding (app_branding row) tambien es async: en el primer frame
    // `valueOrNull` es null y Gate 0 NO redirige (para evitar un flash a
    // /setup mientras carga). Cuando la query resuelve, necesitamos que
    // el router re-evalue para mandar al wizard si `setup_completed=false`,
    // o para echar a alguien que esta en /setup si ya esta completado.
    _brandingSub = _ref.listen(
      appBrandingProvider,
      (_, __) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<dynamic> _authSub;
  late final ProviderSubscription<dynamic> _roleSub;
  late final ProviderSubscription<dynamic> _brandingSub;

  @override
  void dispose() {
    _authSub.close();
    _roleSub.close();
    _brandingSub.close();
    super.dispose();
  }
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({this.error});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64),
            const SizedBox(height: 16),
            Text(error?.toString() ?? '404'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.goNamed(RouteNames.welcome),
              child: const Text('Home'),
            ),
          ],
        ),
      ),
    );
  }
}
