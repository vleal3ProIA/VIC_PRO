import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class EmailVerifiedPage extends StatelessWidget {
  const EmailVerifiedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: 480,
          icon: Icons.verified_outlined,
          title: l.verifyEmailVerifiedTitle,
          subtitle: l.verifyEmailVerifiedSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.goNamed(RouteNames.login),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(l.actionSignIn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
