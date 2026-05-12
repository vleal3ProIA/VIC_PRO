import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/presentation/widgets/auth_failure_message.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class VerifyEmailSentPage extends ConsumerStatefulWidget {
  const VerifyEmailSentPage({required this.email, super.key});

  final String email;

  @override
  ConsumerState<VerifyEmailSentPage> createState() =>
      _VerifyEmailSentPageState();
}

class _VerifyEmailSentPageState extends ConsumerState<VerifyEmailSentPage> {
  bool _sending = false;

  Future<void> _resend() async {
    setState(() => _sending = true);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.resendVerificationEmail(widget.email);
    if (!mounted) return;
    result.match(
      (failure) => context.showSnack(
        authFailureMessage(context, failure),
        isError: true,
      ),
      (_) => context.showSnack(context.l10n.verifyEmailResent),
    );
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: 560,
          leading: Icon(
            Icons.mark_email_read_outlined,
            size: 64,
            color: context.colors.primary,
          ),
          title: l.verifyEmailSentTitle,
          subtitle: l.verifyEmailSentSubtitle(widget.email),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                l.verifyEmailSentResendHint,
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: _sending ? null : _resend,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _sending
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(l.actionResend),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.goNamed(RouteNames.login),
                child: Text(l.actionBackToLogin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
