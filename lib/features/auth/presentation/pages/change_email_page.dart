import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/presentation/widgets/change_email_form.dart';

class ChangeEmailPage extends StatelessWidget {
  const ChangeEmailPage({super.key});

  static const double _reservedHeight = 500;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.accountSettings),
        ),
        title: Text(l.settingsChangeEmail),
      ),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          leading: Icon(
            Icons.mail_outline,
            size: 56,
            color: context.colors.primary,
          ),
          title: l.changeEmailTitle,
          subtitle: l.changeEmailSubtitle,
          child: const ChangeEmailForm(),
        ),
      ),
    );
  }
}
