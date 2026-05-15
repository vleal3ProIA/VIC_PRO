import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/presentation/pages/account_settings_page.dart';
import 'package:myapp/features/admin/presentation/pages/admin_page.dart';
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
import 'package:myapp/features/billing/presentation/pages/billing_success_page.dart';
import 'package:myapp/features/billing/presentation/pages/plans_page.dart';
import 'package:myapp/features/flags/presentation/pages/admin_flags_page.dart';
import 'package:myapp/features/home/presentation/pages/home_page.dart';
import 'package:myapp/features/legal/presentation/pages/cookies_page.dart';
import 'package:myapp/features/legal/presentation/pages/privacy_page.dart';
import 'package:myapp/features/legal/presentation/pages/terms_page.dart';
import 'package:myapp/features/shell/presentation/widgets/private_shell.dart';
import 'package:myapp/features/tenants/presentation/pages/accept_invite_page.dart';
import 'package:myapp/features/tenants/presentation/pages/team_page.dart';
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
        path: RoutePaths.auditLog,
        name: RouteNames.auditLog,
        builder: (_, __) => const AuditLogPage(),
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
  RoutePaths.mfaSetup,
  RoutePaths.accountSettings,
  RoutePaths.changePassword,
  RoutePaths.changePasswordDone,
  RoutePaths.changeEmail,
  RoutePaths.changeEmailSent,
  RoutePaths.deleteAccount,
  RoutePaths.passkeys,
  RoutePaths.auditLog,
  RoutePaths.team,
  RoutePaths.plans,
  RoutePaths.billingSuccess,
  // `acceptInvite` se gestiona dentro de la propia página: si no hay sesión,
  // redirige al login él mismo. No la metemos como privada para que un
  // usuario sin sesión pueda al menos VER el error si el link es inválido.
};

/// Rutas que además requieren rol `admin`. Un usuario autenticado sin ese
/// rol que las pida es redirigido a `/home`.
const _adminRoutes = <String>{
  RoutePaths.admin,
  RoutePaths.adminFlags,
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

String? _redirect(Ref ref, GoRouterState state) {
  final loc = state.matchedLocation;
  if (_excludedFromGuard.contains(loc)) return null;

  // Leemos la sesión DIRECTAMENTE del cliente, no de `isAuthenticatedProvider`.
  // Ese provider se alimenta del stream `onAuthStateChange`, que entrega los
  // eventos de forma asíncrona: justo tras un `signIn` el provider aún puede
  // estar "stale" (false) aunque la sesión ya exista. `currentSession` es la
  // verdad en memoria del SDK y siempre está fresca. `_AuthRefreshNotifier`
  // sigue disparando la re-evaluación; aquí solo cambiamos QUÉ se lee.
  final isAuthed = ref.read(supabaseClientProvider).auth.currentSession != null;

  // 1) No autenticado y la ruta requiere sesión → login.
  if (!isAuthed && _privateRoutes.contains(loc)) {
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

  return null;
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
