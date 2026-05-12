import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/auth/presentation/pages/auth_callback_page.dart';
import 'package:myapp/features/auth/presentation/pages/email_verified_page.dart';
import 'package:myapp/features/auth/presentation/pages/login_page.dart';
import 'package:myapp/features/auth/presentation/pages/register_page.dart';
import 'package:myapp/features/auth/presentation/pages/verify_email_sent_page.dart';
import 'package:myapp/features/welcome/presentation/pages/welcome_page.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RoutePaths.welcome,
    debugLogDiagnostics: true,
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
    ],
    errorBuilder: (_, state) => _NotFoundPage(error: state.error),
  );
});

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
