import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/branding_providers.dart';
import '../../domain/app_branding.dart';
import '../widgets/palette_picker.dart';

/// `/admin/app-branding` — Edita el branding del deploy en cualquier
/// momento. Distinta de `/admin/branding` (que gestiona Stripe).
/// Cambia nombre, paleta, logo, favicon, email de soporte, y el flag
/// `registration_enabled` (gate de `/register`).
///
/// Cualquier cambio se aplica en caliente: al guardar invalidamos el
/// provider y el `MaterialApp` rebuildea con la nueva paleta + título +
/// favicon.
class AdminAppBrandingPage extends ConsumerWidget {
  const AdminAppBrandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.admin),
        ),
        title: Text(l.adminAppBrandingTitle),
      ),
      body: const AdminAppBrandingView(),
    );
  }
}

/// Cuerpo del editor de branding de la app (sin Scaffold). Reutilizable como
/// página completa o embebido en el master-detail de Administración.
class AdminAppBrandingView extends ConsumerStatefulWidget {
  const AdminAppBrandingView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Admin).
  final bool embedded;

  @override
  ConsumerState<AdminAppBrandingView> createState() =>
      _AdminAppBrandingViewState();
}

class _AdminAppBrandingViewState extends ConsumerState<AdminAppBrandingView> {
  final _formKey = GlobalKey<FormState>();
  final _commercialName = TextEditingController();
  final _tagline = TextEditingController();
  final _supportEmail = TextEditingController();
  final _websiteUrl = TextEditingController();
  final _logoUrl = TextEditingController();
  final _logoDarkUrl = TextEditingController();
  final _faviconUrl = TextEditingController();
  final _ogImageUrl = TextEditingController();
  String _paletteSlug = 'blue';
  bool _registrationEnabled = false;
  bool _saving = false;
  bool _hydrated = false;

  @override
  void dispose() {
    _commercialName.dispose();
    _tagline.dispose();
    _supportEmail.dispose();
    _websiteUrl.dispose();
    _logoUrl.dispose();
    _logoDarkUrl.dispose();
    _faviconUrl.dispose();
    _ogImageUrl.dispose();
    super.dispose();
  }

  void _hydrate(AppBranding b) {
    if (_hydrated) return;
    _hydrated = true;
    _commercialName.text = b.commercialName;
    _tagline.text = b.tagline ?? '';
    _supportEmail.text = b.supportEmail ?? '';
    _websiteUrl.text = b.websiteUrl ?? '';
    _logoUrl.text = b.logoUrl ?? '';
    _logoDarkUrl.text = b.logoDarkUrl ?? '';
    _faviconUrl.text = b.faviconUrl ?? '';
    _ogImageUrl.text = b.ogImageUrl ?? '';
    _paletteSlug = b.colorPalette;
    _registrationEnabled = b.registrationEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(appBrandingProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
        child: async.when(
          loading: () => const AppLoadingState(),
          error: (e, _) => AppErrorState(
            message: l.adminAppBrandingLoadError,
            detail: e.toString(),
            onRetry: () => ref.invalidate(appBrandingProvider),
            retryLabel: l.actionRetry,
          ),
          data: (branding) {
            _hydrate(branding);
            final form = Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(l.adminAppBrandingSectionCommercial),
                  PremiumCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _commercialName,
                          enabled: !_saving,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: l.setupFieldCommercialName,
                            prefixIcon: const Icon(Icons.storefront_outlined),
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) {
                              return l.setupCommercialNameRequired;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _tagline,
                          enabled: !_saving,
                          maxLength: 160,
                          decoration: InputDecoration(
                            labelText: l.setupFieldTagline,
                            prefixIcon: const Icon(Icons.short_text),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _supportEmail,
                          enabled: !_saving,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: l.setupFieldSupportEmail,
                            prefixIcon: const Icon(Icons.support_agent),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _websiteUrl,
                          enabled: !_saving,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: l.setupFieldWebsiteUrl,
                            prefixIcon: const Icon(Icons.public),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Section(l.adminAppBrandingSectionVisuals),
                  PremiumCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.setupFieldPalette,
                          style: context.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        PalettePicker(
                          selected: _paletteSlug,
                          enabled: !_saving,
                          onSelected: (slug) =>
                              setState(() => _paletteSlug = slug),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _logoUrl,
                          enabled: !_saving,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: l.setupFieldLogoUrl,
                            helperText: l.setupFieldLogoUrlHint,
                            prefixIcon: const Icon(Icons.image_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _logoDarkUrl,
                          enabled: !_saving,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: l.adminAppBrandingLogoDarkUrl,
                            helperText: l.adminAppBrandingLogoDarkUrlHint,
                            prefixIcon: const Icon(
                              Icons.dark_mode_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _faviconUrl,
                          enabled: !_saving,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: l.setupFieldFaviconUrl,
                            helperText: l.setupFieldFaviconUrlHint,
                            prefixIcon: const Icon(Icons.bookmark_outline),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _ogImageUrl,
                          enabled: !_saving,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: l.adminAppBrandingOgImageUrl,
                            helperText: l.adminAppBrandingOgImageUrlHint,
                            prefixIcon: const Icon(Icons.share_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Section(l.adminAppBrandingSectionAccess),
                  PremiumCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _registrationEnabled,
                          onChanged: _saving
                              ? null
                              : (v) => setState(
                                    () => _registrationEnabled = v,
                                  ),
                          title: Text(
                            l.adminAppBrandingRegistrationEnabled,
                          ),
                          subtitle: Text(
                            l.adminAppBrandingRegistrationEnabledHint,
                          ),
                          secondary: Icon(
                            _registrationEnabled
                                ? Icons.lock_open
                                : Icons.lock_outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PremiumButton(
                      label: l.actionSave,
                      leadingIcon: Icons.save_outlined,
                      loading: _saving,
                      onPressed: _saving ? null : _onSave,
                    ),
                  ),
                ],
              ),
            );
            return widget.embedded
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: form,
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: form,
                  );
          },
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    final l = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      // Helper: pasamos null si está vacío, así limpiamos el campo en
      // BD (en vez de guardar el string vacío que falla los checks).
      String? blankToNull(String s) => s.trim().isEmpty ? null : s.trim();

      await ref.read(brandingDataSourceProvider).update({
        'commercial_name': _commercialName.text.trim(),
        'tagline': blankToNull(_tagline.text),
        'support_email': blankToNull(_supportEmail.text),
        'website_url': blankToNull(_websiteUrl.text),
        'logo_url': blankToNull(_logoUrl.text),
        'logo_dark_url': blankToNull(_logoDarkUrl.text),
        'favicon_url': blankToNull(_faviconUrl.text),
        'og_image_url': blankToNull(_ogImageUrl.text),
        'color_palette': _paletteSlug,
        'registration_enabled': _registrationEnabled,
      });
      if (!mounted) return;
      ref.invalidate(appBrandingProvider);
      context.showSnack(l.adminAppBrandingSaved);
    } catch (e) {
      if (!mounted) return;
      context.showSnack(l.adminAppBrandingSaveError, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: context.textTheme.labelMedium?.copyWith(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
