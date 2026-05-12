import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

/// Placeholder de login con la misma estructura visual (card de tamaño fijo)
/// que el resto de pantallas auth. El form real con email+password se
/// implementará en el siguiente paso de Fase 2.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: 520,
          leading: Icon(
            Icons.lock_open_outlined,
            size: 56,
            color: context.colors.primary,
          ),
          title: l.loginTitle,
          subtitle: l.loginSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Login form coming next 🚧',
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l.loginNoAccount, style: context.textTheme.bodyMedium),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => context.goNamed(RouteNames.register),
                    child: Text(l.loginCreateOne),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
