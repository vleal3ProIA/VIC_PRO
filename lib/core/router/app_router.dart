import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/last_panel_provider.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/router/router_guards.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/presentation/pages/account_sessions_page.dart';
import 'package:myapp/features/account/presentation/pages/account_settings_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_error_detail_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_errors_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_material_library_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_public_domain_sources_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_subject_view_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_trash_page.dart';
import 'package:myapp/features/admin_acl/application/admin_acl_providers.dart';
import 'package:myapp/features/admin_acl/presentation/pages/admin_admins_page.dart';
import 'package:myapp/features/admin_metrics/presentation/pages/admin_metrics_page.dart';
import 'package:myapp/features/admin_users/presentation/pages/admin_user_detail_page.dart';
import 'package:myapp/features/admin_users/presentation/pages/admin_users_page.dart';
import 'package:myapp/features/ai_providers/presentation/pages/admin_ai_providers_page.dart';
import 'package:myapp/features/audit/presentation/pages/activity_feed_page.dart';
import 'package:myapp/features/audit/presentation/pages/audit_log_page.dart';
import 'package:myapp/features/audit_center/presentation/pages/admin_audit_page.dart';
import 'package:myapp/features/audit_center/presentation/pages/admin_audit_report_page.dart';
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
import 'package:myapp/features/subjects/presentation/pages/my_material_kind_page.dart';
import 'package:myapp/features/subjects/presentation/pages/my_material_page.dart';
import 'package:myapp/features/subjects/presentation/pages/my_material_subject_page.dart';
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
/// **Critico** que dependa del stream `authStateChangesProvider`:
/// Riverpod cachea el valor de un Provider hasta que alguna de sus
/// dependencias cambia. Sin el `ref.watch(authStateChangesProvider)`,
/// el provider se evaluaria a `false` al cargar /login, quedaria
/// cacheado, y un `signIn` posterior NO invalidaria el cache -> el
/// guard del router veria estado stale y el user se quedaria en /login
/// tras pulsar "iniciar sesion" (solo despues de un F5 que recrea el
/// container funcionaria).
///
/// El stream NO modifica el valor que devolvemos -- seguimos leyendo
/// el getter `currentSession` que es siempre fresco. Solo lo usamos
/// como TRIGGER para que Riverpod invalide el cache en cada signIn /
/// signOut / token refresh.
///
/// Existe como provider separado para que los tests E2E del router
/// puedan overridearlo con `true` / `false` sin tener que construir un
/// `Session` real ni inicializar el cliente Supabase. Ver
/// `test/core/router/app_router_guards_test.dart`.
final routerIsAuthenticatedProvider = Provider<bool>((ref) {
  // Trigger de re-evaluacion: cualquier cambio en el stream de auth
  // invalida este provider y la proxima lectura lee currentSession
  // fresco. Sin esto, queda cacheado al primer read y nunca se actualiza.
  ref.watch(authStateChangesProvider);
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
            path: RoutePaths.myMaterial,
            name: RouteNames.myMaterial,
            builder: (_, __) => const MyMaterialPage(),
          ),
          // Drill-down: dashboard del temario con contadores por tipo.
          // Va aqui dentro del ShellRoute privado (igual que /mis-temarios)
          // para que herede el shell con la nav lateral. El path es mas
          // especifico que /mis-temarios pero GoRouter no se confunde:
          // /mis-temarios casa exact, /mis-temarios/:id casa con id.
          GoRoute(
            path: RoutePaths.myMaterialSubject,
            name: RouteNames.myMaterialSubject,
            builder: (_, state) => MyMaterialSubjectPage(
              subjectId: state.pathParameters['id'] ?? '',
            ),
          ),
          // Drill-down nivel 2: vista por tipo (quiz, flashcards, notas...).
          // Mismo razonamiento; GoRouter elige la mas larga al matchear.
          GoRoute(
            path: RoutePaths.myMaterialSubjectKind,
            name: RouteNames.myMaterialSubjectKind,
            builder: (_, state) => MyMaterialKindPage(
              subjectId: state.pathParameters['id'] ?? '',
              kind: state.pathParameters['kind'] ?? '',
            ),
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
        path: RoutePaths.adminAudit,
        name: RouteNames.adminAudit,
        builder: (_, __) => const AdminAuditPage(),
      ),
      // Pipeline de errores backend (admin + super_admin). El detalle
      // muestra el unico sitio de la app donde se exponen detalles
      // tecnicos sin pasar por `mapBackendError`.
      GoRoute(
        path: RoutePaths.adminErrors,
        name: RouteNames.adminErrors,
        builder: (_, __) => const AdminErrorsPage(),
      ),
      GoRoute(
        path: RoutePaths.adminErrorDetail,
        name: RouteNames.adminErrorDetail,
        builder: (_, state) => AdminErrorDetailPage(
          errorId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: RoutePaths.adminAuditDetail,
        name: RouteNames.adminAuditDetail,
        builder: (_, state) => AdminAuditReportPage(
          reportId: state.pathParameters['id'] ?? '',
        ),
      ),
      // SOLO super admin. El guard del router (`isSuperAdminRoute` +
      // `evaluateRouterRedirect`) ya echa a quien no sea super; aqui no
      // hay segunda capa de UI -- la pagina asume super.
      GoRoute(
        path: RoutePaths.adminAdmins,
        name: RouteNames.adminAdmins,
        builder: (_, __) => const AdminAdminsPage(),
      ),
      GoRoute(
        path: RoutePaths.adminAiProviders,
        name: RouteNames.adminAiProviders,
        builder: (_, __) => const AdminAiProvidersPage(),
      ),
      // SOLO super admin. El guard del router (`isSuperAdminRoute`) ya
      // bloquea a admins normales antes de llegar. Defensa: la RPC
      // `admin_list_subjects` valida `is_super_admin()` server-side.
      GoRoute(
        path: RoutePaths.adminMaterialLibrary,
        name: RouteNames.adminMaterialLibrary,
        builder: (_, __) => const AdminMaterialLibraryPage(),
      ),
      GoRoute(
        path: RoutePaths.adminMaterialLibrarySubject,
        name: RouteNames.adminMaterialLibrarySubject,
        builder: (_, state) => AdminSubjectViewPage(
          subjectId: state.pathParameters['id'] ?? '',
        ),
      ),
      // SOLO super admin. Gestion de whitelist de fuentes de dominio
      // publico (BOE, .gov, wikipedia.org, etc). Defensa server-side:
      // RLS de `public_domain_sources` exige `is_super_admin()` en write.
      GoRoute(
        path: RoutePaths.adminPublicDomainSources,
        name: RouteNames.adminPublicDomainSources,
        builder: (_, __) => const AdminPublicDomainSourcesPage(),
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
  // PR-Super-A2: leemos las capabilities del user (set vacio mientras carga
  // / sin sesion) y si es super (derivado del propio set, ver provider).
  // El guard usa estos dos para:
  //   - bloquear /admin/admins a non-super (`isSuperAdminRoute`).
  //   - bloquear paginas admin concretas a admins sin la capability
  //     correspondiente (mapeo en `kRouteToCapability`).
  // Si capabilities aun esta cargando (set vacio porque la RPC no
  // resolvio), el guard 2d hace skip para evitar flash.
  final caps =
      ref.read(myCapabilitiesProvider).valueOrNull ?? const <String>{};
  final isSuper = ref.read(isSuperAdminProvider).valueOrNull ?? false;
  final result = evaluateRouterRedirect(
    matchedLocation: state.matchedLocation,
    isAuthenticated: ref.read(routerIsAuthenticatedProvider),
    branding: ref.read(appBrandingProvider).valueOrNull,
    mfaPending: ref.read(mfaChallengePendingProvider),
    isAdmin: ref.read(isAdminProvider),
    onboardingCompleted: ref.read(onboardingCompletedProvider).valueOrNull,
    isSuperAdmin: isSuper,
    capabilities: caps,
  );

  // ─────────────── "Resume last Panel" override (migracion 0085) ─────────
  // Si el guard puro mandaria al user autenticado a /home porque acaba de
  // entrar via login/welcome, y el user tiene un last Panel guardado,
  // sustituimos el destino por `/home?subjectId=<id>&nodeId=<id>` para
  // abrir directo el ultimo Panel donde lo dejo.
  //
  // - Solo aplicamos cuando el destino es /home (asi no interferimos con
  //   /admin/*, MFA challenge, setup, etc.).
  // - Solo aplicamos cuando el origen es una ruta "post-login" (welcome,
  //   login, register, magic-link, etc.) -- evitamos el caso "el user esta
  //   navegando dentro de la app y pulsa Home".
  // - Si el provider del last-panel aun no resolvio (`valueOrNull == null`),
  //   no overrideamos -- el _AuthRefreshNotifier escucha el provider y
  //   re-evalua cuando llegue el dato, asi el destino correcto se aplica
  //   con un re-route en cuanto la query resuelva.
  if (result == RoutePaths.home && _isPostLoginEntry(state.matchedLocation)) {
    final lp = ref.read(lastPanelLocationProvider).valueOrNull;
    if (lp != null && lp.hasPanel) {
      final qp = <String, String>{'subjectId': lp.subjectId!};
      if (lp.nodeId != null) qp['nodeId'] = lp.nodeId!;
      return Uri(path: RoutePaths.home, queryParameters: qp).toString();
    }
  }

  return result;
}

/// `true` si la ruta de origen es una "puerta de entrada" tipica post-login:
/// welcome (root), login, register y los flujos publicOnly. Solo en estos
/// casos sustituimos /home por el ultimo Panel — un user navegando dentro
/// de la app (p.ej. clicando "Home" desde /admin) NO debe ser redirigido.
bool _isPostLoginEntry(String loc) {
  if (loc == RoutePaths.welcome) return true;
  if (publicOnly.contains(loc)) return true;
  return false;
}

/// Adaptador entre el `StreamProvider<AuthState>` y el `Listenable` que
/// `GoRouter.refreshListenable` espera. Cada vez que cambia el estado de
/// auth, notificamos para que el router re-evalúe `redirect`.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(this._ref) {
    _authSub = _ref.listen(
      authStateChangesProvider,
      (_, __) => _scheduleNotify(),
    );
    // El rol llega de forma asíncrona (al cargar el perfil). Re-evaluamos
    // el redirect cuando cambia, para que el guard de rutas solo-admin no
    // se quede con un rol "stale".
    _roleSub = _ref.listen(
      currentRoleProvider,
      (_, __) => _scheduleNotify(),
    );
    // El branding (app_branding row) tambien es async: en el primer frame
    // `valueOrNull` es null y Gate 0 NO redirige (para evitar un flash a
    // /setup mientras carga). Cuando la query resuelve, necesitamos que
    // el router re-evalue para mandar al wizard si `setup_completed=false`,
    // o para echar a alguien que esta en /setup si ya esta completado.
    _brandingSub = _ref.listen(
      appBrandingProvider,
      (_, __) => _scheduleNotify(),
    );
    // PR-Super-A2: capabilities tambien son async (RPC `get_my_capabilities`).
    // Mientras carga, el guard 2d skipea check para evitar flash; cuando
    // resuelve, necesitamos re-evaluar el redirect para que un admin sin
    // capability X que llego a /admin/X (por bookmark / URL directa)
    // sea echado a /admin en cuanto sepamos su lista real.
    _capsSub = _ref.listen(
      myCapabilitiesProvider,
      (_, __) => _scheduleNotify(),
    );
    // "Resume last Panel" (migracion 0085): el provider que lee
    // `profiles.last_subject_id` es async. Justo despues del login, el
    // redirect sincronos ve `valueOrNull == null` y cae al /home por
    // defecto. Cuando la query resuelve, necesitamos re-evaluar para
    // sustituir el destino por el Panel — _isPostLoginEntry sigue
    // matcheando el origen (matchedLocation es /login o welcome), asi que
    // el override se aplica con un re-route en cuanto los datos llegan.
    _lastPanelSub = _ref.listen(
      lastPanelLocationProvider,
      (_, __) => _scheduleNotify(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<dynamic> _authSub;
  late final ProviderSubscription<dynamic> _roleSub;
  late final ProviderSubscription<dynamic> _brandingSub;
  late final ProviderSubscription<dynamic> _capsSub;
  late final ProviderSubscription<dynamic> _lastPanelSub;

  bool _disposed = false;
  bool _notifyScheduled = false;

  /// Coalesce + difiere la notificación al router.
  ///
  /// Los 4 providers (auth, role, branding, capabilities) suelen cambiar
  /// casi a la vez (p. ej. al hacer login, o al cargar el perfil). Notificar
  /// de forma SÍNCRONA dentro del callback de `ref.listen` hace que go_router
  /// re-evalúe el redirect y navegue MIENTRAS Riverpod aún está despachando
  /// la notificación del provider; al montar/desmontar pantallas que observan
  /// esos mismos providers se muta la lista de observers que Riverpod está
  /// iterando → "Concurrent modification during iteration".
  ///
  /// Posponer la notificación a un microtask la saca de ese ciclo y, de paso,
  /// fusiona varias notificaciones simultáneas en una sola re-evaluación del
  /// router (menos trabajo, mismo resultado).
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub.close();
    _roleSub.close();
    _brandingSub.close();
    _capsSub.close();
    _lastPanelSub.close();
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
