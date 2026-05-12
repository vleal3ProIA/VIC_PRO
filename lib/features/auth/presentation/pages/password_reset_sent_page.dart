import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class PasswordResetSentPage extends StatelessWidget {
  const PasswordResetSentPage({required this.email, super.key});

  final String email;

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
            Icons.mark_email_read_outlined,
            size: 64,
            color: context.colors.primary,
          ),
          title: l.forgotPasswordSentTitle,
          subtitle: l.forgotPasswordSentSubtitle(email),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => context.goNamed(RouteNames.login),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(l.actionBackToLogin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
