import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/utils/app_logger.dart';

/// Pantalla a la que Supabase devuelve al usuario tras pulsar el link del
/// email de verificación.
///
/// El SDK ya intercepta el fragment/query y restaura la sesión; aquí solo
/// esperamos un tick para confirmar y redirigimos a /email-verified.
class AuthCallbackPage extends ConsumerStatefulWidget {
  const AuthCallbackPage({super.key});

  @override
  ConsumerState<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends ConsumerState<AuthCallbackPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _process());
  }

  Future<void> _process() async {
    final client = ref.read(supabaseClientProvider);
    try {
      // Si el flujo es PKCE, intercambiamos el code por sesión.
      // Si es magic-link clásico, el SDK ya restauró la sesión solo.
      final uri = Uri.base;
      final code = uri.queryParameters['code'];
      if (code != null) {
        await client.auth.exchangeCodeForSession(code);
      }
      // Si todo OK, hay sesión activa. La welcome o el home lo verán.
      if (!mounted) return;
      context.goNamed(RouteNames.emailVerified);
    } catch (e, st) {
      AppLogger.e('auth callback failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _error = context.l10n.verifyEmailCallbackError);
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
                Text(_error!, style: context.textTheme.bodyLarge),
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
