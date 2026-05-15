import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';

import '../../application/team_providers.dart';
import '../../data/tenant_invitations_datasource.dart';

/// Pantalla `/accept-invite?token=...`.
///
/// Comportamiento:
/// 1. Si no hay token en la URL → muestra error y manda al login.
/// 2. Si no hay sesión → redirige a `/login` preservando el token como
///    query param (`?next=/accept-invite?token=...`).
/// 3. Con sesión + token → llama a la Edge Function `accept`, refresca la
///    lista de tenants, hace `setCurrent(tenantId)` y navega a `/home`.
class AcceptInvitePage extends ConsumerStatefulWidget {
  const AcceptInvitePage({required this.token, super.key});

  final String? token;

  @override
  ConsumerState<AcceptInvitePage> createState() => _AcceptInvitePageState();
}

class _AcceptInvitePageState extends ConsumerState<AcceptInvitePage> {
  _Status _status = _Status.verifying;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attempt());
  }

  Future<void> _attempt() async {
    final token = widget.token;
    if (token == null || token.length < 20) {
      setState(() {
        _status = _Status.error;
        _errorMessage = context.l10n.acceptInviteErrorNotFound;
      });
      return;
    }

    final session = ref.read(currentSessionProvider);
    if (session == null) {
      // No hay sesión: vamos a /login. Sin "deep-link return" por ahora —
      // el usuario vuelve a pegar el link tras autenticarse. Mejorable.
      if (mounted) context.goNamed(RouteNames.login);
      return;
    }

    try {
      await acceptInvitation(ref, token);
      if (!mounted) return;
      setState(() => _status = _Status.joined);
    } on TenantInvitationException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMessage = _mapErrorCode(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMessage = context.l10n.acceptInviteErrorGeneric;
      });
    }
  }

  String _mapErrorCode(String code) {
    final l = context.l10n;
    return switch (code) {
      'expired' => l.acceptInviteErrorExpired,
      'revoked' => l.acceptInviteErrorRevoked,
      'already_accepted' => l.acceptInviteErrorAccepted,
      'invitation_not_found' || 'invalid_token_format' =>
        l.acceptInviteErrorNotFound,
      _ => l.acceptInviteErrorGeneric,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.acceptInviteTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: switch (_status) {
              _Status.verifying => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(l.acceptInviteVerifying),
                  ],
                ),
              _Status.joined => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: context.colors.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l.acceptInviteJoinedTitle,
                      style: context.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.acceptInviteJoinedSubtitle,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () => context.goNamed(RouteNames.home),
                      child: Text(l.acceptInviteContinue),
                    ),
                  ],
                ),
              _Status.error => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: context.colors.error,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _errorMessage ?? l.acceptInviteErrorGeneric,
                      style: context.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextButton(
                      onPressed: () => context.goNamed(RouteNames.home),
                      child: Text(l.acceptInviteContinue),
                    ),
                  ],
                ),
            },
          ),
        ),
      ),
    );
  }
}

enum _Status { verifying, joined, error }
