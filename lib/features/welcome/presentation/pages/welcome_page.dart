import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/seo/meta_tags_sync.dart';
import 'package:myapp/core/seo/seo_meta.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/features/branding/application/branding_providers.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Branding del deploy — nombre comercial + tagline + logo opcional.
    // Si aún no se ha cargado, usamos los fallbacks de i18n existentes.
    final branding = ref.watch(brandingOrFallbackProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logoUrl = branding.logoFor(isDark: isDark);

    // SEO runtime: actualiza meta tags al entrar. Si el branding tiene
    // tagline, lo usamos como description.
    final seoDescription = (branding.tagline?.isNotEmpty ?? false)
        ? branding.tagline!
        : context.l10n.comingSoonSubtitle;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: Column(
        children: [
          MetaTagsSync(
            meta: SeoMeta(
              title: branding.commercialName,
              description: seoDescription,
              ogImageUrl: branding.ogImageUrl,
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 80,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (logoUrl != null)
                        Image.network(
                          logoUrl,
                          height: context.isMobile ? 96 : 144,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              _HeroBadge(mobile: context.isMobile),
                        )
                      else
                        _HeroBadge(mobile: context.isMobile),
                      const SizedBox(height: 32),
                      Text(
                        branding.commercialName,
                        style: context.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (branding.tagline?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        Text(
                          branding.tagline!,
                          style: context.textTheme.titleMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.underConstruction,
                        style: context.textTheme.headlineSmall?.copyWith(
                          color: context.colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.comingSoonSubtitle,
                        style: context.textTheme.bodyLarge?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SafeArea(top: false, child: _LegalFooter()),
        ],
      ),
    );
  }
}

/// Hero "app icon" Premium para la welcome cuando no hay logo de
/// branding (o si la imagen falla). Badge redondeado tintado con el
/// icono de "en construccion" — mismo lenguaje visual que los badges
/// de AuthCard y los tiles del panel admin.
class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.mobile});

  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final box = mobile ? 112.0 : 160.0;
    final iconSize = mobile ? 60.0 : 84.0;
    final primary = context.colors.primary;
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(mobile ? 28 : 36),
        border: Border.all(color: primary.withValues(alpha: 0.16)),
        boxShadow: AppShadows.card(Theme.of(context).brightness),
      ),
      child: Icon(
        Icons.engineering_outlined,
        size: iconSize,
        color: primary,
      ),
    );
  }
}

/// Pie de página público con los enlaces legales obligatorios.
class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final style = context.textTheme.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          TextButton(
            onPressed: () => context.goNamed(RouteNames.terms),
            child: Text(l.termsTitle),
          ),
          Text('·', style: style),
          TextButton(
            onPressed: () => context.goNamed(RouteNames.privacy),
            child: Text(l.privacyTitle),
          ),
          Text('·', style: style),
          TextButton(
            onPressed: () => context.goNamed(RouteNames.cookies),
            child: Text(l.cookiesTitle),
          ),
          Text('·', style: style),
          TextButton(
            onPressed: () => context.goNamed(RouteNames.status),
            child: Text(l.statusFooterLink),
          ),
        ],
      ),
    );
  }
}
