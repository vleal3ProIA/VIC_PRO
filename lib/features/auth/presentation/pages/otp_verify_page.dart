import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/application/otp_verify_notifier.dart';
import 'package:myapp/features/auth/presentation/widgets/otp_verify_form.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class OtpVerifyPage extends ConsumerWidget {
  const OtpVerifyPage({required this.email, super.key});

  final String email;

  static const double _reservedHeight = 720;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Leemos solo `codeLength` para no rebuild la página entera al cambiar
    // el código tecleado.
    final codeLength = ref.watch(
      otpVerifyNotifierProvider(email).select((s) => s.codeLength),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          leading: Icon(
            Icons.dialpad_outlined,
            size: 56,
            color: context.colors.primary,
          ),
          title: context.l10n.otpVerifyTitle,
          subtitle: context.l10n.otpVerifySubtitle(codeLength, email),
          child: OtpVerifyForm(email: email),
        ),
      ),
    );
  }
}
