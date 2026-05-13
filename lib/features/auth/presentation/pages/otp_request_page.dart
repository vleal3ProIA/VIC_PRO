import 'package:flutter/material.dart';

import 'package:myapp/core/config/env_config.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/presentation/widgets/otp_request_form.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class OtpRequestPage extends StatelessWidget {
  const OtpRequestPage({super.key});

  static const double _reservedHeight = 580;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          leading: Icon(
            Icons.pin_outlined,
            size: 56,
            color: context.colors.primary,
          ),
          title: context.l10n.otpRequestTitle,
          subtitle: context.l10n.otpRequestSubtitle(EnvConfig.otpCodeLength),
          child: const OtpRequestForm(),
        ),
      ),
    );
  }
}
