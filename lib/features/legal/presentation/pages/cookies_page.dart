import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/legal/application/cookie_consent_notifier.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

/// Página `/cookies` — política de cookies + preferencias de consentimiento.
///
/// Mezcla parte estática (qué cookies usamos, por categorías) y parte
/// interactiva (toggle de la categoría analytics, único opt-in real hoy).
class CookiesPage extends ConsumerWidget {
  const CookiesPage({super.key});

  /// Fecha de última revisión del documento.
  static const String lastUpdated = '2026-05-15';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final consent = ref.watch(cookieConsentNotifierProvider);
    final notifier = ref.read(cookieConsentNotifierProvider.notifier);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.cookiesTitle,
                    style: context.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.legalLastUpdated(lastUpdated),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Aviso de borrador.
                  _InfoBox(message: l.legalDraftNotice),
                  const SizedBox(height: 24),

                  // Texto explicativo + secciones.
                  Text(
                    l.cookiesIntro,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ----- Categoría: Esenciales (siempre activas) -----
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.lock_outline,
                        color: context.colors.primary,
                      ),
                      title: Text(
                        l.cookiesEssentialTitle,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(l.cookiesEssentialBody),
                      ),
                      trailing: const Switch(
                        value: true,
                        onChanged: null, // siempre activa
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ----- Categoría: Analytics (opt-in) -----
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.analytics_outlined,
                        color: context.colors.primary,
                      ),
                      title: Text(
                        l.cookiesAnalyticsTitle,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(l.cookiesAnalyticsBody),
                      ),
                      trailing: Switch(
                        value: consent.analytics,
                        onChanged: (v) =>
                            notifier.setAnalytics(value: v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    l.cookiesContact,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    child: TextButton.icon(
                      onPressed: () =>
                          context.goNamed(RouteNames.welcome),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: Text(l.actionGoHome),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
