import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/utils/app_logger.dart';
import 'package:myapp/features/auth/application/auth_redirect.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla a la que Supabase devuelve al usuario tras pulsar el link del
/// email (signup confirmation, recovery de password o magic link).
///
/// Importante: el SDK de `supabase_flutter` **ya intercambia automáticamente**
/// el `?code=...` por una sesión al inicializarse en web. NO debemos llamar
/// `exchangeCodeForSession` manualmente — eso consume el `code_verifier`
/// dos veces y dispara `AuthException: Code verifier could not be found`.
///
/// Aquí solo:
///   1. Detectamos errores en la URL (`?error_code=...`).
///   2. Esperamos a tener sesión activa (el SDK la pone en milisegundos).
///   3. Redirigimos según `?type=`:
///        - `signup`    → `/email-verified`
///        - `recovery`  → `/set-new-password`
///        - `magiclink` / `otp` → `/home`
class AuthCallbackPage extends ConsumerStatefulWidget {
  const AuthCallbackPage({super.key});

  @override
  ConsumerState<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends ConsumerState<AuthCallbackPage> {
  static const Duration _waitTimeout = Duration(seconds: 12);

  String? _error;
  String? _errorDetails;
  StreamSubscription<AuthState>? _sub;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _process());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  Future<void> _process() async {
    final client = ref.read(supabaseClientProvider);
    final uri = Uri.base;
    final errorCode = uri.queryParameters['error_code'];
    final errorDescription = uri.queryParameters['error_description'];
    final typeRaw = uri.queryParameters['type'];
    final type = _parseType(typeRaw);

    AppLogger.i(
      'auth callback: type=$typeRaw '
      'session=${client.auth.currentSession != null ? "present" : "absent"} '
      'errorCode=$errorCode',
    );

    // Supabase a veces devuelve errores en query (link expirado/usado).
    if (errorCode != null) {
      setState(() {
        _error = context.l10n.verifyEmailCallbackError;
        _errorDetails = errorDescription ?? errorCode;
      });
      return;
    }

    // Si la sesión ya está activa (el SDK procesó el code mientras se
    // construía la pantalla), redirigimos inmediato.
    if (client.auth.currentSession != null) {
      _redirectByType(type);
      return;
    }

    // Si no, escuchamos el stream y redirigimos al primer evento con sesión.
    _sub = client.auth.onAuthStateChange.listen((event) {
      AppLogger.i('auth callback: stream event=${event.event}');
      if (event.session != null) {
        _sub?.cancel();
        _timeout?.cancel();
        if (mounted) _redirectByType(type);
      }
    });

    // Si después de 12s no aparece sesión, abortamos con error legible.
    _timeout = Timer(_waitTimeout, () {
      _sub?.cancel();
      if (mounted) {
        setState(() {
          _error = context.l10n.verifyEmailCallbackError;
          _errorDetails =
              'Session was not restored in ${_waitTimeout.inSeconds}s.';
        });
      }
    });
  }

  void _redirectByType(AuthRedirectType type) {
    switch (type) {
      case AuthRedirectType.recovery:
        context.goNamed(RouteNames.setNewPassword);
      case AuthRedirectType.magiclink:
      case AuthRedirectType.otp:
        context.goNamed(RouteNames.home);
      case AuthRedirectType.signup:
        context.goNamed(RouteNames.emailVerified);
    }
  }

  AuthRedirectType _parseType(String? raw) {
    switch (raw) {
      case 'recovery':
        return AuthRedirectType.recovery;
      case 'magiclink':
        return AuthRedirectType.magiclink;
      case 'otp':
        return AuthRedirectType.otp;
      case 'signup':
        return AuthRedirectType.signup;
      default:
        return AuthRedirectType.signup;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  l.verifyEmailCallbackProcessing,
                  style: context.textTheme.bodyLarge,
                ),
              ] else ...[
                Icon(
                  Icons.error_outline,
                  size: 56,
                  color: context.colors.error,
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyLarge,
                      ),
                      if (_errorDetails != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _errorDetails!,
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.goNamed(RouteNames.login),
                  child: Text(l.actionBackToLogin),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
