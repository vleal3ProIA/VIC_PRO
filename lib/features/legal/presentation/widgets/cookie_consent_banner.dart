import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/legal/application/cookie_consent_notifier.dart';

/// Banner GDPR de consentimiento de cookies. Aparece fijo en la parte
/// inferior hasta que el usuario decide (`acceptAll` / `rejectOptional` /
/// personalizar desde `/cookies`). Una vez decidido, no vuelve a mostrarse.
///
/// Decisiones de UX:
/// - Dos botones de **igual peso visual** (Aceptar / Rechazar) — sin dark
///   patterns; el GDPR exige que rechazar sea tan fácil como aceptar.
/// - Enlace "Personalizar" lleva a `/cookies` para opt-in granular y a
///   leer la política.
class CookieConsentBanner extends ConsumerWidget {
  const CookieConsentBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(cookieConsentNotifierProvider);
    if (consent.isDecided) return const SizedBox.shrink();

    final notifier = ref.read(cookieConsentNotifierProvider.notifier);
    final l = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(16),
          color: context.colors.surface,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: context.colors.outlineVariant),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cookie_outlined,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.cookieConsentTitle,
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.cookieConsentBody,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => context.goNamed(RouteNames.cookies),
                        child: Text(l.cookieConsentCustomize),
                      ),
                      OutlinedButton(
                        onPressed: notifier.rejectOptional,
                        child: Text(l.cookieConsentReject),
                      ),
                      FilledButton(
                        onPressed: notifier.acceptAll,
                        child: Text(l.cookieConsentAccept),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
