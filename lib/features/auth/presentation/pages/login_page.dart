import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/presentation/widgets/login_form.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  // Altura reservada para no mover la card al aparecer/desaparecer errores.
  // Acomoda divider + 5 botones outlined (Passkey + Google + Apple +
  // magic link + OTP).
  static const double _reservedHeight = 1000;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          icon: Icons.lock_open_outlined,
          title: context.l10n.loginTitle,
          subtitle: context.l10n.loginSubtitle,
          child: const LoginForm(),
        ),
      ),
    );
  }
}
