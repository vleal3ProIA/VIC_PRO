import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';

import '../../application/billing_info_providers.dart';
import '../../domain/billing_info.dart';
import '../widgets/country_picker.dart';
import '../widgets/tax_id_type_picker.dart';

/// Pantalla `/billing/info` — datos de facturación del usuario.
///
/// Si la URL trae `?return=/path`, tras guardar redirige a esa ruta. Esto
/// lo usa el gate de `/billing/plans` para mandar al usuario a completar
/// datos y devolverlo al catálogo automáticamente.
class BillingInfoPage extends ConsumerStatefulWidget {
  const BillingInfoPage({this.returnTo, super.key});

  /// Ruta a la que volver tras guardar correctamente. Si null, no redirige
  /// (se queda en esta pantalla con snackbar de éxito).
  final String? returnTo;

  @override
  ConsumerState<BillingInfoPage> createState() => _BillingInfoPageState();
}

class _BillingInfoPageState extends ConsumerState<BillingInfoPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _addr1;
  late final TextEditingController _addr2;
  late final TextEditingController _city;
  late final TextEditingController _zip;
  late final TextEditingController _taxId;
  String? _country;
  String? _taxIdType;
  DateTime? _dob;
  bool _busy = false;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController();
    _lastName = TextEditingController();
    _addr1 = TextEditingController();
    _addr2 = TextEditingController();
    _city = TextEditingController();
    _zip = TextEditingController();
    _taxId = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _addr1, _addr2, _city, _zip, _taxId]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(BillingInfo info) {
    if (_hydrated) return;
    _hydrated = true;
    _firstName.text = info.firstName ?? '';
    _lastName.text = info.lastName ?? '';
    _addr1.text = info.addressLine1 ?? '';
    _addr2.text = info.addressLine2 ?? '';
    _city.text = info.city ?? '';
    _zip.text = info.postalCode ?? '';
    _taxId.text = info.taxId ?? '';
    _country = info.country;
    _taxIdType = info.taxIdType;
    _dob = info.dateOfBirth;
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final ds = ref.read(billingInfoDataSourceProvider);
      final info = BillingInfo(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        dateOfBirth: _dob,
        addressLine1: _addr1.text.trim(),
        addressLine2: _addr2.text.trim().isEmpty ? null : _addr2.text.trim(),
        city: _city.text.trim(),
        postalCode: _zip.text.trim(),
        country: _country,
        taxId: _taxId.text.trim().isEmpty ? null : _taxId.text.trim(),
        taxIdType: _taxId.text.trim().isEmpty ? null : _taxIdType,
      );
      // Mandamos null explícito en address_line2 / tax_id si están vacíos.
      final patch = <String, dynamic>{
        'first_name': info.firstName,
        'last_name': info.lastName,
        'date_of_birth': info.dateOfBirth == null
            ? null
            : '${info.dateOfBirth!.year.toString().padLeft(4, '0')}-'
                '${info.dateOfBirth!.month.toString().padLeft(2, '0')}-'
                '${info.dateOfBirth!.day.toString().padLeft(2, '0')}',
        'address_line1': info.addressLine1,
        'address_line2': info.addressLine2,
        'city': info.city,
        'postal_code': info.postalCode,
        'country': info.country,
        'tax_id': info.taxId,
        'tax_id_type': info.taxIdType,
      };
      await ds.updateMine(patch);
      ref.invalidate(myBillingInfoProvider);
      if (!mounted) return;
      context.showSnack(context.l10n.billingInfoSaved);
      if (widget.returnTo != null) {
        context.go(widget.returnTo!);
      }
    } catch (_) {
      if (!mounted) return;
      context.showSnack(context.l10n.billingInfoSaveError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 30, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: context.l10n.billingInfoFieldDob,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final asyncInfo = ref.watch(myBillingInfoProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.accountSettings),
        ),
        title: Text(l.billingInfoTitle),
      ),
      body: asyncInfo.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            l.billingInfoLoadError,
            style: TextStyle(color: context.colors.error),
          ),
        ),
        data: (info) {
          _hydrate(info);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: double.infinity),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.returnTo != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.colors.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: context.colors.tertiary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l.billingInfoCompleteHint,
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: context.colors.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _SectionLabel(text: l.billingInfoSectionPersonal),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _firstName,
                              enabled: !_busy,
                              decoration: InputDecoration(
                                labelText: l.billingInfoFieldFirstName,
                              ),
                              validator: _required,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _lastName,
                              enabled: !_busy,
                              decoration: InputDecoration(
                                labelText: l.billingInfoFieldLastName,
                              ),
                              validator: _required,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _busy ? null : _pickDob,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: l.billingInfoFieldDob,
                            suffixIcon: const Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(
                            _dob == null
                                ? '—'
                                : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel(text: l.billingInfoSectionAddress),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _addr1,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          labelText: l.billingInfoFieldAddressLine1,
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addr2,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          labelText: l.billingInfoFieldAddressLine2,
                          helperText: l.billingInfoFieldAddressLine2Help,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _city,
                              enabled: !_busy,
                              decoration: InputDecoration(
                                labelText: l.billingInfoFieldCity,
                              ),
                              validator: _required,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _zip,
                              enabled: !_busy,
                              decoration: InputDecoration(
                                labelText: l.billingInfoFieldPostalCode,
                              ),
                              validator: _required,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CountryPicker(
                        value: _country,
                        enabled: !_busy,
                        onChanged: (v) => setState(() => _country = v),
                        validator: (v) =>
                            v == null ? l.billingInfoFieldCountryRequired : null,
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel(text: l.billingInfoSectionTax),
                      const SizedBox(height: 4),
                      Text(
                        l.billingInfoTaxHint,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _taxId,
                              enabled: !_busy,
                              decoration: InputDecoration(
                                labelText: l.billingInfoFieldTaxId,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TaxIdTypePicker(
                              value: _taxIdType,
                              enabled: !_busy && _taxId.text.trim().isNotEmpty,
                              onChanged: (v) => setState(() => _taxIdType = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      FilledButton(
                        onPressed: _busy ? null : _onSave,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              )
                            : Text(l.billingInfoSave),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _required(String? v) {
    if (v == null || v.trim().isEmpty) return context.l10n.fieldRequired;
    return null;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: context.textTheme.titleSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      );
}
