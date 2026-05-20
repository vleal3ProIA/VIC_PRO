import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/core/widgets/info_banner.dart';

class ChangeEmailSentPage extends StatelessWidget {
  const ChangeEmailSentPage({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l.settingsChangeEmail),
      ),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: 540,
          icon: Icons.mark_email_read_outlined,
          title: l.changeEmailSentTitle,
          subtitle: l.changeEmailSentSubtitle(email),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              InfoBanner(message: l.magicLinkSentInstruction),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () => context.goNamed(RouteNames.accountSettings),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(l.actionContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
