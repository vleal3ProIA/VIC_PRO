import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/admin_stripe_branding_providers.dart';
import '../../domain/stripe_branding.dart';

/// `/admin/branding` — visualización del branding de la propia cuenta
/// Stripe + deep-link al Dashboard para editarlo.
///
/// **Por qué solo lectura**: Stripe rechaza cualquier update vía API sobre
/// la propia cuenta de plataforma (`POST /v1/account` → 403
/// "You cannot use this method on your own account"). Los settings se
/// editan únicamente desde `https://dashboard.stripe.com/settings/...`.
/// Esta página le ahorra al admin tener que loguearse a Stripe para ver el
/// estado actual, y le lleva en 1 clic a la pantalla correcta para editar.
class AdminBrandingPage extends ConsumerWidget {
  const AdminBrandingPage({super.key});

  static const _dashboardBrandingUrl =
      'https://dashboard.stripe.com/settings/branding';
  static const _dashboardAccountUrl =
      'https://dashboard.stripe.com/settings/account';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final brandingAsync = ref.watch(stripeBrandingProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.admin),
        ),
        title: Text(l.adminBrandingTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(stripeBrandingProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
          child: brandingAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _LoadError(
              message: l.adminBrandingLoadError,
              detail: e.toString(),
            ),
            data: (branding) => _BrandingView(branding: branding),
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.detail});
  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: context.colors.error),
          const SizedBox(height: 12),
          Text(
            message,
            style: context.textTheme.titleMedium?.copyWith(
              color: context.colors.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BrandingView extends StatelessWidget {
  const _BrandingView({required this.branding});
  final StripeBranding branding;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadOnlyBanner(),
          const SizedBox(height: 16),

          // ─────── Logo + colores ───────
          PremiumCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionTitle(l.adminBrandingSectionVisuals),
                const SizedBox(height: 4),
                Text(
                  l.adminBrandingSectionVisualsHint,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _LogoPreview(logoUrl: branding.logoUrl),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ReadOnlyField(
                            label: l.adminBrandingPrimaryColor,
                            value: branding.primaryColor,
                            swatchColor: _parseHex(branding.primaryColor),
                          ),
                          const SizedBox(height: AppSpacing.sm + 4),
                          _ReadOnlyField(
                            label: l.adminBrandingSecondaryColor,
                            value: branding.secondaryColor,
                            swatchColor: _parseHex(branding.secondaryColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: PremiumButton(
                    label: l.adminBrandingOpenDashboardBranding,
                    variant: PremiumButtonVariant.secondary,
                    size: PremiumButtonSize.sm,
                    leadingIcon: Icons.open_in_new,
                    onPressed: () => _openUrl(
                      context,
                      AdminBrandingPage._dashboardBrandingUrl,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ─────── Datos fiscales ───────
          PremiumCard(
            padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionTitle(l.adminBrandingSectionBusiness),
                  const SizedBox(height: 4),
                  Text(
                    l.adminBrandingSectionBusinessHint,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ReadOnlyField(
                    label: l.adminBrandingBusinessName,
                    value: branding.businessName,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ReadOnlyField(
                          label: l.adminBrandingSupportEmail,
                          value: branding.supportEmail,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ReadOnlyField(
                          label: l.adminBrandingSupportPhone,
                          value: branding.supportPhone,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ReadOnlyField(
                    label: l.adminBrandingUrl,
                    value: branding.url,
                  ),
                  const SizedBox(height: 20),
                  _SectionTitle(l.adminBrandingSectionAddress, small: true),
                  const SizedBox(height: 12),
                  _ReadOnlyField(
                    label: l.adminBrandingAddrLine1,
                    value: branding.supportAddress.line1,
                  ),
                  if (branding.supportAddress.line2 != null &&
                      branding.supportAddress.line2!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ReadOnlyField(
                      label: l.adminBrandingAddrLine2,
                      value: branding.supportAddress.line2,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _ReadOnlyField(
                          label: l.adminBrandingAddrCity,
                          value: branding.supportAddress.city,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ReadOnlyField(
                          label: l.adminBrandingAddrPostalCode,
                          value: branding.supportAddress.postalCode,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _ReadOnlyField(
                          label: l.adminBrandingAddrState,
                          value: branding.supportAddress.state,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ReadOnlyField(
                          label: l.adminBrandingAddrCountry,
                          value: branding.supportAddress.country,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PremiumButton(
                      label: l.adminBrandingOpenDashboardAccount,
                      variant: PremiumButtonVariant.secondary,
                      size: PremiumButtonSize.sm,
                      leadingIcon: Icons.open_in_new,
                      onPressed: () => _openUrl(
                        context,
                        AdminBrandingPage._dashboardAccountUrl,
                      ),
                    ),
                  ),
                ],
              ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Color? _parseHex(String? hex) {
    if (hex == null) return null;
    final t = hex.trim();
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(t)) return null;
    return Color(int.parse('FF${t.substring(1)}', radix: 16));
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.adminBrandingOpenDashboardError)),
      );
    }
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Card(
      color: context.colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: context.colors.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.adminBrandingReadOnlyTitle,
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.colors.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.adminBrandingReadOnlyBody,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.small = false});
  final String text;
  final bool small;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: (small ? context.textTheme.titleSmall : context.textTheme.titleMedium)
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({required this.logoUrl});
  final String? logoUrl;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: logoUrl == null
          ? Icon(
              Icons.image_outlined,
              size: 36,
              color: context.colors.onSurfaceVariant,
            )
          : Image.network(
              logoUrl!,
              semanticLabel: 'Stripe branding logo',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image_outlined,
                color: context.colors.onSurfaceVariant,
              ),
            ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    this.swatchColor,
  });
  final String label;
  final String? value;
  final Color? swatchColor;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final v = value?.trim();
    final isEmpty = v == null || v.isEmpty;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: swatchColor == null
            ? null
            : Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: swatchColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: context.colors.outlineVariant),
                  ),
                ),
              ),
        suffixIcon: isEmpty
            ? null
            : IconButton(
                tooltip: l.adminBrandingCopyValue,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: v));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.adminBrandingCopied)),
                  );
                },
              ),
      ),
      child: Text(
        isEmpty ? l.adminBrandingFieldEmpty : v,
        style: context.textTheme.bodyLarge?.copyWith(
          color: isEmpty
              ? context.colors.onSurfaceVariant
              : context.colors.onSurface,
          fontStyle: isEmpty ? FontStyle.italic : null,
        ),
      ),
    );
  }
}
