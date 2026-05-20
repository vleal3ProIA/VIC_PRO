import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';

class ChangePasswordDonePage extends StatelessWidget {
  const ChangePasswordDonePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l.settingsChangePassword),
      ),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: 460,
          icon: Icons.check_circle_outline,
          iconColor: context.colors.tertiary,
          title: l.changePasswordSuccessTitle,
          subtitle: l.changePasswordSuccessSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              FilledButton(
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
