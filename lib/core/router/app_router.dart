import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/account/presentation/pages/account_settings_page.dart';
import 'package:myapp/features/auth/application/mfa_providers.dart';
import 'package:myapp/features/auth/presentation/pages/auth_callback_page.dart';
import 'package:myapp/features/auth/presentation/pages/email_verified_page.dart';
import 'package:myapp/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:myapp/features/auth/presentation/pages/login_page.dart';
import 'package:myapp/features/auth/presentation/pages/magic_link_page.dart';
import 'package:myapp/features/auth/presentation/pages/magic_link_sent_page.dart';
import 'package:myapp/features/auth/presentation/pages/mfa_challenge_page.dart';
import 'package:myapp/features/auth/presentation/pages/mfa_setup_page.dart';
import 'package:myapp/features/auth/presentation/pages/otp_request_page.dart';
import 'package:myapp/features/auth/presentation/pages/otp_verify_page.dart';
import 'package:myapp/features/auth/presentation/pages/password_reset_sent_page.dart';
import 'package:myapp/features/auth/presentation/pages/password_updated_page.dart';
import 'package:myapp/features/auth/presentation/pages/register_page.dart';
import 'package:myapp/features/auth/presentation/pages/set_new_password_page.dart';
import 'package:myapp/features/auth/presentation/pages/verify_email_sent_page.dart';
import 'package:myapp/features/home/presentation/pages/home_page.dart';
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
const _excludedFromGuard = <String>{
  RoutePaths.authCallback,
  RoutePaths.setNewPassword,
  RoutePaths.passwordUpdated,
  RoutePaths.emailVerified,
  RoutePaths.verifyEmailSent,
};

/// Rutas privadas (requieren sesión activa).
const _privateRoutes = <String>{
  RoutePaths.home,
  RoutePaths.mfaSetup,
  RoutePaths.accountSettings,
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

  final isAuthed = ref.read(isAuthenticatedProvider);

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
    _sub = _ref.listen(
      authStateChangesProvider,
      (_, __) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.close();
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
