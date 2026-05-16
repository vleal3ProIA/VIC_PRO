import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/admin_stripe_branding_providers.dart';
import '../../data/admin_stripe_branding_datasource.dart';
import '../../domain/stripe_branding.dart';

/// `/admin/branding` — gestión del branding y datos fiscales de la propia
/// cuenta Stripe de la plataforma. Permite cambiar:
///
///   - **Colores**: primary + secondary (hex `#RRGGBB`). Se reflejan en las
///     páginas hospedadas de Stripe (Checkout, invoice pages).
///   - **Logo**: PNG/JPEG/GIF/WEBP hasta 4MB. Aparece en facturas PDF.
///   - **Datos fiscales**: nombre comercial, email/teléfono de soporte,
///     URL pública, dirección postal (línea 1, línea 2, ciudad, CP,
///     provincia/estado, país ISO-2).
///
/// Todas las operaciones pasan por la Edge Function
/// `admin-stripe-branding` (JWT + role=admin + rate limit 30/h).
class AdminBrandingPage extends ConsumerWidget {
  const AdminBrandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final brandingAsync = ref.watch(stripeBrandingProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.admin),
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
          constraints: const BoxConstraints(maxWidth: 880),
          child: brandingAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _LoadError(
              message: l.adminBrandingLoadError,
              detail: e.toString(),
            ),
            data: (branding) => _BrandingForm(initial: branding),
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

class _BrandingForm extends ConsumerStatefulWidget {
  const _BrandingForm({required this.initial});
  final StripeBranding initial;

  @override
  ConsumerState<_BrandingForm> createState() => _BrandingFormState();
}

class _BrandingFormState extends ConsumerState<_BrandingForm> {
  final _formKey = GlobalKey<FormState>();

  // Colors.
  late TextEditingController _primaryColor;
  late TextEditingController _secondaryColor;

  // Business profile.
  late TextEditingController _businessName;
  late TextEditingController _supportEmail;
  late TextEditingController _url;
  late TextEditingController _supportPhone;

  // Address.
  late TextEditingController _addrLine1;
  late TextEditingController _addrLine2;
  late TextEditingController _addrCity;
  late TextEditingController _addrPostalCode;
  late TextEditingController _addrState;
  late TextEditingController _addrCountry;

  bool _savingBranding = false;
  bool _savingBusiness = false;
  bool _uploadingLogo = false;

  @override
  void initState() {
    super.initState();
    final b = widget.initial;
    _primaryColor = TextEditingController(text: b.primaryColor ?? '');
    _secondaryColor = TextEditingController(text: b.secondaryColor ?? '');
    _businessName = TextEditingController(text: b.businessName ?? '');
    _supportEmail = TextEditingController(text: b.supportEmail ?? '');
    _url = TextEditingController(text: b.url ?? '');
    _supportPhone = TextEditingController(text: b.supportPhone ?? '');
    _addrLine1 = TextEditingController(text: b.supportAddress.line1 ?? '');
    _addrLine2 = TextEditingController(text: b.supportAddress.line2 ?? '');
    _addrCity = TextEditingController(text: b.supportAddress.city ?? '');
    _addrPostalCode =
        TextEditingController(text: b.supportAddress.postalCode ?? '');
    _addrState = TextEditingController(text: b.supportAddress.state ?? '');
    _addrCountry = TextEditingController(text: b.supportAddress.country ?? '');
  }

  @override
  void dispose() {
    _primaryColor.dispose();
    _secondaryColor.dispose();
    _businessName.dispose();
    _supportEmail.dispose();
    _url.dispose();
    _supportPhone.dispose();
    _addrLine1.dispose();
    _addrLine2.dispose();
    _addrCity.dispose();
    _addrPostalCode.dispose();
    _addrState.dispose();
    _addrCountry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final b = widget.initial;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─────── Logo + colores ───────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _LogoPreview(logoUrl: b.logoUrl),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.upload_outlined),
                                label: Text(l.adminBrandingChangeLogo),
                                onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l.adminBrandingLogoConstraints,
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                              if (_uploadingLogo) ...[
                                const SizedBox(height: 8),
                                const LinearProgressIndicator(),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _HexColorField(
                            controller: _primaryColor,
                            label: l.adminBrandingPrimaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _HexColorField(
                            controller: _secondaryColor,
                            label: l.adminBrandingSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.save_outlined),
                        label: Text(l.adminBrandingSaveColors),
                        onPressed: _savingBranding ? null : _saveBranding,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─────── Datos fiscales ───────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                    TextFormField(
                      controller: _businessName,
                      decoration: InputDecoration(
                        labelText: l.adminBrandingBusinessName,
                        prefixIcon: const Icon(Icons.business_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _supportEmail,
                            decoration: InputDecoration(
                              labelText: l.adminBrandingSupportEmail,
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return null;
                              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                                return l.adminBrandingInvalidEmail;
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _supportPhone,
                            decoration: InputDecoration(
                              labelText: l.adminBrandingSupportPhone,
                              prefixIcon: const Icon(Icons.phone_outlined),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _url,
                      decoration: InputDecoration(
                        labelText: l.adminBrandingUrl,
                        prefixIcon: const Icon(Icons.public_outlined),
                        hintText: 'https://...',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(l.adminBrandingSectionAddress, small: true),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addrLine1,
                      decoration: InputDecoration(
                        labelText: l.adminBrandingAddrLine1,
                        prefixIcon: const Icon(Icons.home_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addrLine2,
                      decoration: InputDecoration(
                        labelText: l.adminBrandingAddrLine2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _addrCity,
                            decoration: InputDecoration(
                              labelText: l.adminBrandingAddrCity,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _addrPostalCode,
                            decoration: InputDecoration(
                              labelText: l.adminBrandingAddrPostalCode,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _addrState,
                            decoration: InputDecoration(
                              labelText: l.adminBrandingAddrState,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _addrCountry,
                            decoration: InputDecoration(
                              labelText: l.adminBrandingAddrCountry,
                              hintText: 'ES',
                            ),
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 2,
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return null;
                              if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(t)) {
                                return l.adminBrandingInvalidCountry;
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.save_outlined),
                        label: Text(l.adminBrandingSaveBusiness),
                        onPressed: _savingBusiness ? null : _saveBusiness,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────── Handlers ─────────────────────────────

  Future<void> _saveBranding() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final l = context.l10n;
    final primary = _primaryColor.text.trim();
    final secondary = _secondaryColor.text.trim();

    if (primary.isEmpty && secondary.isEmpty) {
      _toast(l.adminBrandingNothingToUpdate);
      return;
    }

    setState(() => _savingBranding = true);
    try {
      final ds = ref.read(adminStripeBrandingDataSourceProvider);
      await ds.updateBranding(
        primaryColor: primary.isEmpty ? null : primary,
        secondaryColor: secondary.isEmpty ? null : secondary,
      );
      if (!mounted) return;
      _toast(l.adminBrandingSaved);
      ref.invalidate(stripeBrandingProvider);
    } on StripeBrandingException catch (e) {
      if (!mounted) return;
      _toast(_friendlyError(l, e.code, detail: e.detail));
    } catch (e) {
      if (!mounted) return;
      _toast(l.adminBrandingSaveError);
    } finally {
      if (mounted) setState(() => _savingBranding = false);
    }
  }

  Future<void> _saveBusiness() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final l = context.l10n;
    final addr = StripeSupportAddress(
      line1: _addrLine1.text,
      line2: _addrLine2.text,
      city: _addrCity.text,
      postalCode: _addrPostalCode.text,
      state: _addrState.text,
      country: _addrCountry.text.toUpperCase(),
    );

    final hasAnyAddr = addr.toUpdateMap().isNotEmpty;
    final name = _businessName.text.trim();
    final email = _supportEmail.text.trim();
    final url = _url.text.trim();
    final phone = _supportPhone.text.trim();

    if (name.isEmpty && email.isEmpty && url.isEmpty && phone.isEmpty && !hasAnyAddr) {
      _toast(l.adminBrandingNothingToUpdate);
      return;
    }

    setState(() => _savingBusiness = true);
    try {
      final ds = ref.read(adminStripeBrandingDataSourceProvider);
      await ds.updateBusiness(
        name: name.isEmpty ? null : name,
        supportEmail: email.isEmpty ? null : email,
        url: url.isEmpty ? null : url,
        supportPhone: phone.isEmpty ? null : phone,
        supportAddress: hasAnyAddr ? addr : null,
      );
      if (!mounted) return;
      _toast(l.adminBrandingSaved);
      ref.invalidate(stripeBrandingProvider);
    } on StripeBrandingException catch (e) {
      if (!mounted) return;
      _toast(_friendlyError(l, e.code, detail: e.detail));
    } catch (e) {
      if (!mounted) return;
      _toast(l.adminBrandingSaveError);
    } finally {
      if (mounted) setState(() => _savingBusiness = false);
    }
  }

  Future<void> _pickAndUploadLogo() async {
    final l = context.l10n;
    final picker = ImagePicker();
    final XFile? file;
    try {
      file = await picker.pickImage(source: ImageSource.gallery);
    } catch (_) {
      if (!mounted) return;
      _toast(l.adminBrandingPickError);
      return;
    }
    if (file == null) return;

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      _toast(l.adminBrandingPickError);
      return;
    }
    if (bytes.length > 4 * 1024 * 1024) {
      if (!mounted) return;
      _toast(l.adminBrandingLogoTooLarge);
      return;
    }

    final mime = _guessMime(file.name);
    if (mime == null) {
      if (!mounted) return;
      _toast(l.adminBrandingLogoUnsupported);
      return;
    }

    setState(() => _uploadingLogo = true);
    try {
      final ds = ref.read(adminStripeBrandingDataSourceProvider);
      await ds.uploadLogo(
        filename: file.name,
        mimeType: mime,
        bytes: bytes,
      );
      if (!mounted) return;
      _toast(l.adminBrandingLogoUploaded);
      ref.invalidate(stripeBrandingProvider);
    } on StripeBrandingException catch (e) {
      if (!mounted) return;
      _toast(_friendlyError(l, e.code, detail: e.detail));
    } catch (e) {
      if (!mounted) return;
      _toast(l.adminBrandingLogoUploadError);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  String? _guessMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return null;
  }

  String _friendlyError(AppLocalizations l, String code, {String? detail}) {
    switch (code) {
      case 'invalid_color':
        return l.adminBrandingInvalidColor;
      case 'rate_limited':
        return l.adminBrandingRateLimited;
      case 'not_admin':
        return l.adminBrandingNotAdmin;
      case 'file_too_large':
        return l.adminBrandingLogoTooLarge;
      case 'unsupported_mime':
        return l.adminBrandingLogoUnsupported;
      case 'nothing_to_update':
        return l.adminBrandingNothingToUpdate;
      case 'stripe_error':
        // Mostramos el mensaje literal de Stripe (URL inválida, teléfono mal
        // formateado, etc.) para que el admin sepa qué corregir.
        return detail == null || detail.isEmpty
            ? l.adminBrandingSaveError
            : 'Stripe: $detail';
      default:
        return l.adminBrandingSaveError;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image_outlined,
                color: context.colors.onSurfaceVariant,
              ),
            ),
    );
  }
}

class _HexColorField extends StatelessWidget {
  const _HexColorField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: '#1F2937',
        prefixIcon: _ColorSwatch(controller: controller),
      ),
      maxLength: 7,
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return null;
        if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(t)) {
          return l.adminBrandingInvalidColor;
        }
        return null;
      },
      onChanged: (_) {
        // Force prefix swatch repaint by triggering a microtask rebuild —
        // TextEditingController notifies and InputDecorator rebuilds.
      },
    );
  }
}

class _ColorSwatch extends StatefulWidget {
  const _ColorSwatch({required this.controller});
  final TextEditingController controller;
  @override
  State<_ColorSwatch> createState() => _ColorSwatchState();
}

class _ColorSwatchState extends State<_ColorSwatch> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text.trim();
    Color? color;
    if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(text)) {
      color = Color(int.parse('FF${text.substring(1)}', radix: 16));
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color ?? Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: color == null
            ? Icon(
                Icons.colorize_outlined,
                size: 14,
                color: context.colors.onSurfaceVariant,
              )
            : null,
      ),
    );
  }
}
