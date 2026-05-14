import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/presentation/widgets/register_form.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  // Altura reservada para que la card NO cambie de tamaño cuando aparecen
  // o desaparecen los slots de error. Calculada para acomodar 4 inputs
  // + slot general + checkbox + enlaces legales + botones + divider
  // + Google + Apple + link.
  static const double _reservedHeight = 980;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          leading: Icon(
            Icons.person_add_alt_1_outlined,
            size: 56,
            color: context.colors.primary,
          ),
          title: context.l10n.registerTitle,
          subtitle: context.l10n.registerSubtitle,
          child: const RegisterForm(),
        ),
      ),
    );
  }
}
