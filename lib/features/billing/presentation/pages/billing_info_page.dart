import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/billing_info_providers.dart';
import '../../domain/billing_info.dart';
import '../widgets/country_picker.dart';
import '../widgets/tax_id_type_picker.dart';

/// Pantalla `/billing/info` — datos de facturación del usuario.
///
/// Comportamiento:
///  - Por defecto se muestran los datos como una CARD DE LECTURA (sin
///    inputs) y un icono de lápiz arriba a la derecha para entrar en modo
///    edición.
///  - Si el usuario aún no ha rellenado NADA, se muestra un empty state
///    sin inputs invitando a añadir los datos.
///  - El modo edición sustituye la card de lectura por el formulario.
///    Tras guardar correctamente, volvemos a la card de lectura.
///  - Caso especial: si llegan con `?return=/path` (el gate de
///    /billing/plans manda al usuario aquí para completar datos), entramos
///    DIRECTAMENTE en modo edición — es la intención obvia del usuario.
class BillingInfoPage extends ConsumerWidget {
  const BillingInfoPage({this.returnTo, super.key});

  /// Ruta a la que volver tras guardar correctamente. Si null, no redirige
  /// (se queda en esta pantalla con snackbar de éxito).
  final String? returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.accountSettings),
        ),
        title: Text(l.billingInfoTitle),
      ),
      body: BillingInfoView(returnTo: returnTo),
    );
  }
}

/// Cuerpo del formulario de datos de facturación (sin Scaffold). Reutilizable
/// como página completa o embebido en el master-detail de Ajustes →
/// Facturación.
class BillingInfoView extends ConsumerStatefulWidget {
  const BillingInfoView({this.returnTo, this.embedded = false, super.key});

  /// Ruta a la que volver tras guardar correctamente. Si null, no redirige
  /// (se queda con snackbar de éxito).
  final String? returnTo;

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Ajustes).
  final bool embedded;

  @override
  ConsumerState<BillingInfoView> createState() => _BillingInfoViewState();
}

class _BillingInfoViewState extends ConsumerState<BillingInfoView> {
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

  /// Modo edición. `false` = card de lectura con icono de lápiz; `true` =
  /// formulario con inputs. Si llegamos con `returnTo`, el usuario viene a
  /// completar datos: entramos directamente en edición.
  bool _editing = false;

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
    if (widget.returnTo != null) _editing = true;
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _lastName,
      _addr1,
      _addr2,
      _city,
      _zip,
      _taxId,
    ]) {
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

  /// Re-sincroniza los controllers con el estado canónico de BD (descarta
  /// cambios sin guardar). Lo usamos al cancelar la edición.
  void _resetFromCurrent(BillingInfo info) {
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
      } else {
        // Tras guardar volvemos a la card de lectura para confirmar
        // visualmente que los datos quedaron persistidos.
        setState(() => _editing = false);
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

    return asyncInfo.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(
          l.billingInfoLoadError,
          style: TextStyle(color: context.colors.error),
        ),
      ),
      data: (info) {
        _hydrate(info);
        final Widget body = _editing
            ? _buildEditForm(context, info)
            : _buildReadOnlyCard(context, info);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            child: widget.embedded
                ? Padding(padding: const EdgeInsets.all(16), child: body)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: body,
                  ),
          ),
        );
      },
    );
  }

  // ──────────────── Card de SOLO LECTURA (con lápiz para editar) ────────────

  Widget _buildReadOnlyCard(BuildContext context, BillingInfo info) {
    final l = context.l10n;
    final empty = !info.hasAnyData;
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera: título a la izquierda + lápiz a la derecha. El lápiz
          // entra en modo edición; en el empty state usamos un botón
          // primario "Añadir datos" más visible.
          Row(
            children: [
              Expanded(
                child: Text(
                  l.billingInfoTitle,
                  style: context.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (!empty)
                IconButton(
                  tooltip: l.billingInfoEditAction,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => setState(() => _editing = true),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (empty)
            _EmptyStateBlock(
              onAdd: () => setState(() => _editing = true),
            )
          else ...[
            _ReadSection(
              title: l.billingInfoSectionPersonal,
              rows: [
                _Row(l.billingInfoFieldFirstName, info.firstName),
                _Row(l.billingInfoFieldLastName, info.lastName),
                _Row(l.billingInfoFieldDob, _formatDate(info.dateOfBirth)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _ReadSection(
              title: l.billingInfoSectionAddress,
              rows: [
                _Row(l.billingInfoFieldAddressLine1, info.addressLine1),
                _Row(l.billingInfoFieldAddressLine2, info.addressLine2),
                _Row(l.billingInfoFieldCity, info.city),
                _Row(l.billingInfoFieldPostalCode, info.postalCode),
                _Row(
                  l.billingInfoFieldCountry,
                  CountryPicker.displayNameFor(info.country).isEmpty
                      ? null
                      : CountryPicker.displayNameFor(info.country),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _ReadSection(
              title: l.billingInfoSectionTax,
              rows: [
                _Row(l.billingInfoFieldTaxId, info.taxId),
                _Row(
                  l.billingInfoFieldTaxIdType,
                  (info.taxId != null && info.taxId!.trim().isNotEmpty)
                      ? info.taxIdType
                      : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String? _formatDate(DateTime? d) {
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // ──────────────── Formulario (modo EDICIÓN) ──────────────────────────────

  Widget _buildEditForm(BuildContext context, BillingInfo currentInfo) {
    final l = context.l10n;
    return Form(
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
          // Cancel + Guardar. Cancel descarta los cambios sin guardar y
          // vuelve a la card de lectura. Cuando venimos del flow de planes
          // (`returnTo`) no mostramos Cancel — el usuario debe completar.
          Row(
            children: [
              if (widget.returnTo == null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _resetFromCurrent(currentInfo);
                              _editing = false;
                            }),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(l.actionCancel),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: widget.returnTo == null ? 1 : 1,
                child: FilledButton(
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
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _required(String? v) {
    if (v == null || v.trim().isEmpty) return context.l10n.fieldRequired;
    return null;
  }
}

// ───────────────────────────── Widgets auxiliares ───────────────────────────

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

/// Bloque de una sección en SOLO LECTURA: título + filas de label/valor.
class _ReadSection extends StatelessWidget {
  const _ReadSection({required this.title, required this.rows});

  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(text: title),
        const SizedBox(height: AppSpacing.sm),
        for (final r in rows) _ReadRow(label: r.label, value: r.value),
      ],
    );
  }
}

/// Tupla label/valor para la vista de SOLO LECTURA.
class _Row {
  const _Row(this.label, this.value);
  final String label;
  final String? value;
}

/// Fila individual: label a la izquierda + valor a la derecha. Si el valor
/// es null/vacío, mostramos un guion atenuado para que la fila siga teniendo
/// estructura coherente.
class _ReadRow extends StatelessWidget {
  const _ReadRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final shown = (value == null || value!.trim().isEmpty) ? '—' : value!;
    final isEmpty = value == null || value!.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              shown,
              style: context.textTheme.bodyMedium?.copyWith(
                color: isEmpty
                    ? context.colors.onSurfaceVariant
                    : context.colors.onSurface,
                fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state cuando el usuario NO tiene ningún dato de facturación
/// guardado: icono + mensaje + botón primario para añadir.
class _EmptyStateBlock extends StatelessWidget {
  const _EmptyStateBlock({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l.billingInfoEmptyTitle,
                textAlign: TextAlign.center,
                style: context.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                l.billingInfoEmptyBody,
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(l.billingInfoAddAction),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}
