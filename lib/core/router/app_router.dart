import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/presentation/pages/account_sessions_page.dart';
import 'package:myapp/features/account/presentation/pages/account_settings_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_trash_page.dart';
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
import 'package:myapp/features/tenants/presentation/pages/accept_invite_page.dart';
import 'package:myapp/features/tenants/presentation/pages/team_page.dart';
import 'package:myapp/features/tokens/presentation/pages/tokens_page.dart';
import 'package:myapp/features/uploads/presentation/pages/files_page.dart';
import 'package:myapp/features/webhooks/presentation/pages/webhook_detail_page.dart';
import 'package:myapp/features/webhooks/presentation/pages/webhooks_page.dart';
import 'package:myapp/features/welcome/presentation/pages/welcome_page.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: RoutePaths.welcome,
    debugLogDiagnostics: true,
    refreshListenable: refreshNotifier,
    redirect: (context, state) => _redirect(ref, state),
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

/// Rutas que NO se ven afectadas por los guards de auth:
/// - `/auth/callback` siempre debe poder procesar el code.
/// - `/set-new-password` requiere sesión activa (la del recovery) y NO debe
///   redirigir a /home al detectar sesión.
/// - `/password-updated` cierra sesión al entrar, así que debe poder mostrarse.
/// - `/email-verified` igualmente: visible sin importar el estado.
/// - `/terms` y `/privacy` son documentos legales: accesibles siempre, con o
///   sin sesión (se enlazan desde el registro y el footer público).
const _excludedFromGuard = <String>{
  RoutePaths.authCallback,
  RoutePaths.setNewPassword,
  RoutePaths.passwordUpdated,
  RoutePaths.emailVerified,
  RoutePaths.verifyEmailSent,
  RoutePaths.emailChanged,
  RoutePaths.terms,
  RoutePaths.privacy,
  RoutePaths.cookies,
};

/// Rutas privadas (requieren sesión activa).
const _privateRoutes = <String>{
  RoutePaths.home,
  RoutePaths.admin,
  RoutePaths.adminFlags,
  RoutePaths.adminPlans,
  RoutePaths.adminBranding,
  RoutePaths.adminCoupons,
  RoutePaths.adminTrash,
  RoutePaths.adminChangelog,
  RoutePaths.adminAppBranding,
  RoutePaths.adminEmailLog,
  RoutePaths.changelog,
  RoutePaths.mfaSetup,
  RoutePaths.accountSettings,
  RoutePaths.changePassword,
  RoutePaths.changePasswordDone,
  RoutePaths.changeEmail,
  RoutePaths.changeEmailSent,
  RoutePaths.deleteAccount,
  RoutePaths.passkeys,
  RoutePaths.sessions,
  RoutePaths.files,
  RoutePaths.tokens,
  RoutePaths.webhooks,
  RoutePaths.notifications,
  RoutePaths.onboarding,
  RoutePaths.auditLog,
  RoutePaths.activity,
  RoutePaths.team,
  RoutePaths.plans,
  RoutePaths.billingSuccess,
  RoutePaths.billingInfo,
  RoutePaths.embeddedCheckout,
  RoutePaths.invoices,
  // `acceptInvite` se gestiona dentro de la propia página: si no hay sesión,
  // redirige al login él mismo. No la metemos como privada para que un
  // usuario sin sesión pueda al menos VER el error si el link es inválido.
};

/// Rutas que además requieren rol `admin`. Un usuario autenticado sin ese
/// rol que las pida es redirigido a `/home`.
const _adminRoutes = <String>{
  RoutePaths.admin,
  RoutePaths.adminFlags,
  RoutePaths.adminPlans,
  RoutePaths.adminBranding,
  RoutePaths.adminCoupons,
  RoutePaths.adminTrash,
  RoutePaths.adminChangelog,
  RoutePaths.adminAppBranding,
  RoutePaths.adminEmailLog,
};

/// Rutas públicas en las que NO queremos estar si ya hay sesión.
const _publicOnly = <String>{
  RoutePaths.login,
  RoutePaths.register,
  RoutePaths.forgotPassword,
  RoutePaths.passwordResetSent,
  RoutePaths.magicLink,
  RoutePaths.magicLinkSent,
  RoutePaths.otpRequest,
  RoutePaths.otpVerify,
};

/// `true` si la ruta necesita sesión. Lista exacta de `_privateRoutes`
/// más los patrones parametrizados que el `Set` exacto no atrapa
/// (ej. `/account-settings/webhooks/<uuid>`).
bool _isPrivate(String loc) {
  if (_privateRoutes.contains(loc)) return true;
  if (loc.startsWith('/account-settings/webhooks/')) return true;
  return false;
}

String? _redirect(Ref ref, GoRouterState state) {
  final loc = state.matchedLocation;
  if (_excludedFromGuard.contains(loc)) return null;

  // ─────────────── Gate 0: setup_completed ───────────────
  // Antes de cualquier otra cosa, si el deploy no ha pasado por
  // /setup, fuerza al usuario a entrar ahí. Excepción: /setup mismo
  // y rutas de auth necesarias para crear el primer admin (el wizard
  // las usa internamente). Tambien excluimos /auth/callback que sirve
  // para confirmar el email del admin si Supabase lo exige.
  final branding = ref.read(brandingOrFallbackProvider);
  if (!branding.setupCompleted && loc != RoutePaths.setup) {
    // Excluimos las rutas que el propio wizard puede necesitar
    // (auth callback de email verify, verify-email-sent).
    const setupAllowed = {
      RoutePaths.authCallback,
      RoutePaths.verifyEmailSent,
      RoutePaths.emailVerified,
    };
    if (!setupAllowed.contains(loc)) {
      return RoutePaths.setup;
    }
  }
  // Si ya está completado y alguien intenta volver a /setup, fuera.
  if (branding.setupCompleted && loc == RoutePaths.setup) {
    return RoutePaths.welcome;
  }

  // Leemos la sesión DIRECTAMENTE del cliente, no de `isAuthenticatedProvider`.
  // Ese provider se alimenta del stream `onAuthStateChange`, que entrega los
  // eventos de forma asíncrona: justo tras un `signIn` el provider aún puede
  // estar "stale" (false) aunque la sesión ya exista. `currentSession` es la
  // verdad en memoria del SDK y siempre está fresca. `_AuthRefreshNotifier`
  // sigue disparando la re-evaluación; aquí solo cambiamos QUÉ se lee.
  final isAuthed = ref.read(supabaseClientProvider).auth.currentSession != null;

  // 1) No autenticado y la ruta requiere sesión → login.
  if (!isAuthed && _isPrivate(loc)) {
    return RoutePaths.login;
  }

  // 1b) Gate de registro: si está cerrado y alguien intenta /register,
  //     lo mandamos a /login con un toast (lo gestiona la propia
  //     pantalla register al detectar la flag).
  if (!isAuthed &&
      loc == RoutePaths.register &&
      !branding.registrationEnabled) {
    return RoutePaths.login;
  }

  // 2) Si está autenticado pero su AAL no es el requerido (MFA pendiente),
  //    cualquier ruta lleva a /mfa-challenge salvo la propia /mfa-challenge.
  if (isAuthed && loc != RoutePaths.mfaChallenge) {
    final pending = ref.read(mfaChallengePendingProvider);
    if (pending) return RoutePaths.mfaChallenge;
  }

  // 2b) Ruta solo-admin y el usuario no tiene ese rol → /home.
  if (isAuthed && _adminRoutes.contains(loc) && !ref.read(isAdminProvider)) {
    return RoutePaths.home;
  }

  // 3) Autenticado (y sin MFA pendiente) en ruta solo para invitados.
  if (isAuthed && _publicOnly.contains(loc)) {
    return RoutePaths.home;
  }

  // 4) Si ya completó MFA y está en /mfa-challenge → /home.
  if (isAuthed && loc == RoutePaths.mfaChallenge) {
    final pending = ref.read(mfaChallengePendingProvider);
    if (!pending) return RoutePaths.home;
  }

  // 5) Onboarding wizard: usuario autenticado sin onboarding completado
  //    se redirige a /onboarding -- excepto si ya está allí o en rutas
  //    transversales que NO queremos bloquear (logout, legal, callback).
  //    Si el provider aún está cargando, NO redirigimos -- evita el
  //    flash de /onboarding antes de saber el estado real.
  if (isAuthed &&
      loc != RoutePaths.onboarding &&
      _onboardingGatedRoutes.contains(loc)) {
    final completedAsync = ref.read(onboardingCompletedProvider);
    final completed = completedAsync.valueOrNull;
    if (completed == false) return RoutePaths.onboarding;
  }

  return null;
}

/// Rutas donde el onboarding gate se aplica. Lista explícita (no
/// "todas las privadas") porque /accept-invite, /change-email-sent y
/// similares deben funcionar incluso pre-onboarding (link en email).
const _onboardingGatedRoutes = <String>{
  RoutePaths.home,
  RoutePaths.admin,
  RoutePaths.accountSettings,
  RoutePaths.plans,
  RoutePaths.billingInfo,
  RoutePaths.invoices,
  RoutePaths.team,
  RoutePaths.notifications,
  RoutePaths.activity,
};

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
  }

  final Ref _ref;
  late final ProviderSubscription<dynamic> _authSub;
  late final ProviderSubscription<dynamic> _roleSub;

  @override
  void dispose() {
    _authSub.close();
    _roleSub.close();
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
