import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';

/// Pantalla a la que llega el usuario tras pulsar el link de confirmación
/// de cambio de email (callback con `type=email_change`).
class EmailChangedPage extends StatelessWidget {
  const EmailChangedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: 460,
          icon: Icons.verified_outlined,
          iconColor: context.colors.tertiary,
          title: l.emailChangedTitle,
          subtitle: l.emailChangedSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.goNamed(RouteNames.home),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(l.actionGoHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
