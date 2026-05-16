import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../application/admin_coupons_providers.dart';
import '../../data/admin_coupons_datasource.dart';
import '../../domain/coupon.dart';
import '../../domain/plan.dart';

/// Dialog "Crear cupón" usado desde `/admin/coupons`. Pop con `true` si
/// el cupón se creó (para que la página invalide el provider de lista).
class AdminCouponCreateDialog extends ConsumerStatefulWidget {
  const AdminCouponCreateDialog({required this.availablePlans, super.key});

  final List<Plan> availablePlans;

  @override
  ConsumerState<AdminCouponCreateDialog> createState() =>
      _AdminCouponCreateDialogState();
}

class _AdminCouponCreateDialogState
    extends ConsumerState<AdminCouponCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _value = TextEditingController();
  final _months = TextEditingController();
  final _maxRedemptions = TextEditingController();

  bool _isPercent = true;
  String _currency = 'EUR';
  CouponDuration _duration = CouponDuration.once;
  DateTime? _redeemBy;
  final Set<String> _selectedPlanSlugs = <String>{};

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _months.dispose();
    _maxRedemptions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.adminCouponsCreateTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: l.adminCouponsFieldName,
                    hintText: 'Black Friday 2026',
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return l.adminCouponsErrNameRequired;
                    if (t.length > 80) return l.adminCouponsErrNameTooLong;
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _TwoColumnRow(
                  children: [
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: true,
                          label: Text(l.adminCouponsTypePercent),
                          icon: const Icon(Icons.percent),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(l.adminCouponsTypeFixed),
                          icon: const Icon(Icons.euro),
                        ),
                      ],
                      selected: {_isPercent},
                      onSelectionChanged: (s) {
                        setState(() {
                          _isPercent = s.first;
                          _value.clear();
                        });
                      },
                    ),
                    if (!_isPercent)
                      DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: InputDecoration(
                          labelText: l.adminCouponsFieldCurrency,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'EUR', child: Text('EUR €')),
                          DropdownMenuItem(value: 'USD', child: Text(r'USD $')),
                          DropdownMenuItem(value: 'GBP', child: Text('GBP £')),
                        ],
                        onChanged: (v) => setState(() => _currency = v ?? 'EUR'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: _isPercent
                        ? l.adminCouponsFieldPercent
                        : l.adminCouponsFieldAmount,
                    suffixText: _isPercent ? '%' : _currency,
                  ),
                  validator: (v) {
                    final raw = (v ?? '').trim().replaceAll(',', '.');
                    if (raw.isEmpty) return l.adminCouponsErrValueRequired;
                    final n = double.tryParse(raw);
                    if (n == null || n <= 0) {
                      return l.adminCouponsErrValueInvalid;
                    }
                    if (_isPercent && n > 100) {
                      return l.adminCouponsErrPercentRange;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  l.adminCouponsFieldDuration,
                  style: context.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l.adminCouponsDurationOnce),
                      selected: _duration == CouponDuration.once,
                      onSelected: (_) => setState(() => _duration = CouponDuration.once),
                    ),
                    ChoiceChip(
                      label: Text(l.adminCouponsDurationRepeating),
                      selected: _duration == CouponDuration.repeating,
                      onSelected: (_) => setState(() => _duration = CouponDuration.repeating),
                    ),
                    ChoiceChip(
                      label: Text(l.adminCouponsDurationForever),
                      selected: _duration == CouponDuration.forever,
                      onSelected: (_) => setState(() => _duration = CouponDuration.forever),
                    ),
                  ],
                ),
                if (_duration == CouponDuration.repeating) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _months,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l.adminCouponsFieldDurationMonths,
                    ),
                    validator: (v) {
                      if (_duration != CouponDuration.repeating) return null;
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 1) {
                        return l.adminCouponsErrMonthsRequired;
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _maxRedemptions,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l.adminCouponsFieldMaxRedemptions,
                    helperText: l.adminCouponsFieldMaxRedemptionsHelp,
                  ),
                ),
                const SizedBox(height: 12),
                _RedeemByPicker(
                  value: _redeemBy,
                  onChanged: (v) => setState(() => _redeemBy = v),
                ),
                const SizedBox(height: 16),
                Text(
                  l.adminCouponsFieldAppliesTo,
                  style: context.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  l.adminCouponsFieldAppliesToHelp,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.availablePlans.isEmpty)
                  Text(
                    l.adminCouponsNoPlans,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: widget.availablePlans.map((p) {
                      final selected = _selectedPlanSlugs.contains(p.slug);
                      return FilterChip(
                        label: Text(p.name),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedPlanSlugs.add(p.slug);
                            } else {
                              _selectedPlanSlugs.remove(p.slug);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _onSubmit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.adminCouponsCreate),
        ),
      ],
    );
  }

  Future<void> _onSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l = context.l10n;
    setState(() => _saving = true);

    final ds = ref.read(adminCouponsDataSourceProvider);
    final rawValue = _value.text.trim().replaceAll(',', '.');
    final numValue = double.parse(rawValue);

    try {
      await ds.createCoupon(
        name: _name.text.trim(),
        percentOff: _isPercent ? numValue : null,
        amountOffCents: _isPercent ? null : (numValue * 100).round(),
        currency: _isPercent ? null : _currency,
        duration: _duration,
        durationInMonths: _duration == CouponDuration.repeating
            ? int.parse(_months.text.trim())
            : null,
        maxRedemptions: _maxRedemptions.text.trim().isEmpty
            ? null
            : int.parse(_maxRedemptions.text.trim()),
        redeemBy: _redeemBy,
        appliesToPlanSlugs: _selectedPlanSlugs.isEmpty
            ? null
            : _selectedPlanSlugs.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AdminCouponException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.detail != null && e.detail!.isNotEmpty
              ? 'Stripe: ${e.detail}'
              : l.adminCouponsActionError,
        ),
      ),);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminCouponsActionError)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _TwoColumnRow extends StatelessWidget {
  const _TwoColumnRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class _RedeemByPicker extends StatelessWidget {
  const _RedeemByPicker({required this.value, required this.onChanged});
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: l.adminCouponsFieldRedeemBy,
        helperText: l.adminCouponsFieldRedeemByHelp,
        suffixIcon: value == null
            ? IconButton(
                tooltip: l.adminCouponsPickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                onPressed: () => _pick(context),
              )
            : IconButton(
                tooltip: l.actionClear,
                icon: const Icon(Icons.close),
                onPressed: () => onChanged(null),
              ),
      ),
      child: InkWell(
        onTap: () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            value == null
                ? l.adminCouponsNoExpiry
                : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
            style: context.textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) onChanged(picked);
  }
}
