import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/entities/sign_up_request.dart';

import '../../application/branding_providers.dart';
import '../widgets/palette_picker.dart';

/// `/setup` — wizard de primera-vez que aparece UNA VEZ por deploy,
/// cuando todavía no hay admin en la BD. Pasos:
///
///   1) Datos comerciales: nombre, tagline, email de soporte
///   2) Identidad visual: paleta + URLs de logo/favicon (opcional)
///   3) Crear primera cuenta admin: email + password
///
/// Al finalizar:
///   - Guardamos branding (UPDATE app_branding)
///   - Registramos el user via auth.signUp
///   - Llamamos a `bootstrap_first_admin()` que lo promociona a admin
///     y marca `setup_completed = true`
///   - Redirigimos a `/home`
///
/// El router se encarga del gate: si `setup_completed == true` y alguien
/// intenta entrar a `/setup`, lo manda a `/welcome`. Y si está en false
/// y alguien intenta entrar a cualquier sitio que no sea `/setup`,
/// lo manda aquí.
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  int _currentStep = 0;
  bool _saving = false;
  String? _errorMsg;

  // Step 1: brand
  final _commercialNameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _supportEmailCtrl = TextEditingController();
  final _websiteUrlCtrl = TextEditingController();

  // Step 2: visuals
  String _paletteSlug = 'blue';
  final _logoUrlCtrl = TextEditingController();
  final _faviconUrlCtrl = TextEditingController();

  // Step 3: first admin
  final _adminEmailCtrl = TextEditingController();
  final _adminPasswordCtrl = TextEditingController();

  final _step1FormKey = GlobalKey<FormState>();
  final _step3FormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _commercialNameCtrl.dispose();
    _taglineCtrl.dispose();
    _supportEmailCtrl.dispose();
    _websiteUrlCtrl.dispose();
    _logoUrlCtrl.dispose();
    _faviconUrlCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l.setupTitle),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.setupIntroTitle,
                      style: context.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.setupIntroBody,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Stepper(
                      currentStep: _currentStep,
                      controlsBuilder: _controlsBuilder,
                      onStepContinue: _saving ? null : _onContinue,
                      onStepCancel: _saving ? null : _onCancel,
                      steps: [
                        Step(
                          title: Text(l.setupStep1Title),
                          subtitle: Text(l.setupStep1Subtitle),
                          isActive: _currentStep >= 0,
                          state: _currentStep > 0
                              ? StepState.complete
                              : StepState.indexed,
                          content: _Step1Brand(
                            formKey: _step1FormKey,
                            commercialName: _commercialNameCtrl,
                            tagline: _taglineCtrl,
                            supportEmail: _supportEmailCtrl,
                            websiteUrl: _websiteUrlCtrl,
                            enabled: !_saving,
                          ),
                        ),
                        Step(
                          title: Text(l.setupStep2Title),
                          subtitle: Text(l.setupStep2Subtitle),
                          isActive: _currentStep >= 1,
                          state: _currentStep > 1
                              ? StepState.complete
                              : StepState.indexed,
                          content: _Step2Visuals(
                            paletteSlug: _paletteSlug,
                            onPaletteChanged: (slug) =>
                                setState(() => _paletteSlug = slug),
                            logoUrl: _logoUrlCtrl,
                            faviconUrl: _faviconUrlCtrl,
                            enabled: !_saving,
                          ),
                        ),
                        Step(
                          title: Text(l.setupStep3Title),
                          subtitle: Text(l.setupStep3Subtitle),
                          isActive: _currentStep >= 2,
                          content: _Step3Admin(
                            formKey: _step3FormKey,
                            email: _adminEmailCtrl,
                            password: _adminPasswordCtrl,
                            enabled: !_saving,
                          ),
                        ),
                      ],
                    ),
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.colors.errorContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: context.colors.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMsg!,
                                style: context.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlsBuilder(BuildContext context, ControlsDetails details) {
    final l = context.l10n;
    final isLast = _currentStep == 2;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          FilledButton(
            onPressed: details.onStepContinue,
            child: _saving && isLast
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isLast ? l.setupFinish : l.actionContinue),
          ),
          if (_currentStep > 0) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: details.onStepCancel,
              child: Text(l.setupBack),
            ),
          ],
        ],
      ),
    );
  }

  void _onCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _onContinue() async {
    setState(() => _errorMsg = null);

    switch (_currentStep) {
      case 0:
        if (!(_step1FormKey.currentState?.validate() ?? false)) return;
        setState(() => _currentStep = 1);
      case 1:
        // Step 2 no tiene validación obligatoria — todo opcional.
        setState(() => _currentStep = 2);
      case 2:
        if (!(_step3FormKey.currentState?.validate() ?? false)) return;
        await _finalize();
    }
  }

  Future<void> _finalize() async {
    final l = context.l10n;
    setState(() {
      _saving = true;
      _errorMsg = null;
    });
    try {
      // 1) Persistir branding (UPDATE atomico al row singleton).
      final ds = ref.read(brandingDataSourceProvider);
      await ds.update({
        'commercial_name': _commercialNameCtrl.text.trim(),
        if (_taglineCtrl.text.trim().isNotEmpty)
          'tagline': _taglineCtrl.text.trim(),
        if (_supportEmailCtrl.text.trim().isNotEmpty)
          'support_email': _supportEmailCtrl.text.trim(),
        if (_websiteUrlCtrl.text.trim().isNotEmpty)
          'website_url': _websiteUrlCtrl.text.trim(),
        if (_logoUrlCtrl.text.trim().isNotEmpty)
          'logo_url': _logoUrlCtrl.text.trim(),
        if (_faviconUrlCtrl.text.trim().isNotEmpty)
          'favicon_url': _faviconUrlCtrl.text.trim(),
        'color_palette': _paletteSlug,
        // setup_completed lo marca la RPC bootstrap_first_admin tras
        // promocionar al user a admin — no lo seteamos aquí porque si
        // el signUp falla queremos que el wizard se siga mostrando.
      });

      // 2) Crear el primer admin via auth.signUp (directo al repo,
      //    sin pasar por el register_notifier que es para el form de
      //    /register con state machine + formz).
      final authRepo = ref.read(authRepositoryProvider);
      final signUpEither = await authRepo.signUp(
        SignUpRequest(
          username: _adminEmailCtrl.text.trim().split('@').first,
          email: _adminEmailCtrl.text.trim(),
          password: _adminPasswordCtrl.text,
          locale: ref.read(effectiveLocaleProvider).languageCode,
          themeMode: ref.read(themeNotifierProvider).name,
        ),
      );
      final signUpResult = signUpEither.fold(
        (failure) => throw Exception('signup_failed: ${failure.runtimeType}'),
        (result) => result,
      );

      // 3) Si Supabase requiere confirmar email, el wizard NO puede
      //    promocionar todavía (no hay sesión activa hasta confirmar).
      //    En ese caso, el siguiente login del nuevo user disparará
      //    bootstrap_first_admin automáticamente (lo añadiremos en una
      //    futura PR de auth-flow polish). Por ahora, redirigimos a
      //    verify-email-sent y dejamos setup_completed = false para que
      //    al confirmar y entrar a /home se reintente.
      if (signUpResult.needsEmailConfirmation) {
        if (!mounted) return;
        ref.invalidate(appBrandingProvider);
        context.goNamed(
          RouteNames.verifyEmailSent,
          queryParameters: {'email': signUpResult.email},
        );
        return;
      }

      // 4) Sesión activa (autoSignIn enabled o sin confirmación):
      //    promovemos a admin + marcamos setup_completed.
      final promoted = await ds.bootstrapFirstAdmin();
      if (!promoted) {
        // No-op si ya había admin (race). No es un error duro; seguimos.
      }

      // 5) Invalidar branding para que la app pinte con la nueva
      //    paleta / nombre comercial.
      if (!mounted) return;
      ref.invalidate(appBrandingProvider);
      context.showSnack(l.setupCompleted);
      context.goNamed(RouteNames.home);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = l.setupError;
        _saving = false;
      });
    }
  }
}

class _Step1Brand extends StatelessWidget {
  const _Step1Brand({
    required this.formKey,
    required this.commercialName,
    required this.tagline,
    required this.supportEmail,
    required this.websiteUrl,
    required this.enabled,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController commercialName;
  final TextEditingController tagline;
  final TextEditingController supportEmail;
  final TextEditingController websiteUrl;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: commercialName,
            enabled: enabled,
            maxLength: 80,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.setupFieldCommercialName,
              helperText: l.setupFieldCommercialNameHint,
              prefixIcon: const Icon(Icons.storefront_outlined),
            ),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return l.setupCommercialNameRequired;
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: tagline,
            enabled: enabled,
            maxLength: 160,
            decoration: InputDecoration(
              labelText: l.setupFieldTagline,
              helperText: l.setupFieldTaglineHint,
              prefixIcon: const Icon(Icons.short_text),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: supportEmail,
            enabled: enabled,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l.setupFieldSupportEmail,
              helperText: l.setupFieldSupportEmailHint,
              prefixIcon: const Icon(Icons.support_agent),
            ),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return null;
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                return l.setupEmailInvalid;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: websiteUrl,
            enabled: enabled,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: l.setupFieldWebsiteUrl,
              helperText: l.setupFieldWebsiteUrlHint,
              prefixIcon: const Icon(Icons.public),
              hintText: 'https://...',
            ),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return null;
              if (!s.startsWith('http://') && !s.startsWith('https://')) {
                return l.setupUrlInvalid;
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}

class _Step2Visuals extends StatelessWidget {
  const _Step2Visuals({
    required this.paletteSlug,
    required this.onPaletteChanged,
    required this.logoUrl,
    required this.faviconUrl,
    required this.enabled,
  });

  final String paletteSlug;
  final ValueChanged<String> onPaletteChanged;
  final TextEditingController logoUrl;
  final TextEditingController faviconUrl;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.setupFieldPalette, style: context.textTheme.labelLarge),
        const SizedBox(height: 8),
        PalettePicker(
          selected: paletteSlug,
          enabled: enabled,
          onSelected: onPaletteChanged,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: logoUrl,
          enabled: enabled,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: l.setupFieldLogoUrl,
            helperText: l.setupFieldLogoUrlHint,
            prefixIcon: const Icon(Icons.image_outlined),
            hintText: 'https://...',
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: faviconUrl,
          enabled: enabled,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: l.setupFieldFaviconUrl,
            helperText: l.setupFieldFaviconUrlHint,
            prefixIcon: const Icon(Icons.bookmark_outline),
            hintText: 'https://.../favicon.ico',
          ),
        ),
      ],
    );
  }
}

class _Step3Admin extends StatelessWidget {
  const _Step3Admin({
    required this.formKey,
    required this.email,
    required this.password,
    required this.enabled,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.setupStep3Body,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: email,
            enabled: enabled,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: l.fieldEmail,
              prefixIcon: const Icon(Icons.alternate_email),
            ),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return l.setupEmailRequired;
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                return l.setupEmailInvalid;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: password,
            enabled: enabled,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: l.fieldPassword,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
            validator: (v) {
              final s = v ?? '';
              if (s.length < 8) return l.setupPasswordTooShort;
              return null;
            },
          ),
        ],
      ),
    );
  }
}
