import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/presentation/widgets/set_new_password_form.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class SetNewPasswordPage extends StatelessWidget {
  const SetNewPasswordPage({super.key});

  static const double _reservedHeight = 620;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          icon: Icons.key_outlined,
          title: context.l10n.setNewPasswordTitle,
          subtitle: context.l10n.setNewPasswordSubtitle,
          child: const SetNewPasswordForm(),
        ),
      ),
    );
  }
}
