import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/presentation/widgets/magic_link_form.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class MagicLinkPage extends StatelessWidget {
  const MagicLinkPage({super.key});

  static const double _reservedHeight = 560;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          leading: Icon(
            Icons.auto_awesome_outlined,
            size: 56,
            color: context.colors.primary,
          ),
          title: context.l10n.magicLinkTitle,
          subtitle: context.l10n.magicLinkSubtitle,
          child: const MagicLinkForm(),
        ),
      ),
    );
  }
}
