import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../application/admin_coupons_providers.dart';
import '../../data/admin_coupons_datasource.dart';
import '../../domain/coupon.dart';

/// Dialog "Crear código promocional" — vinculado a un cupón ya existente.
/// Pop con `true` si se creó (la página recarga).
class AdminPromotionCodeCreateDialog extends ConsumerStatefulWidget {
  const AdminPromotionCodeCreateDialog({required this.coupon, super.key});

  final Coupon coupon;

  @override
  ConsumerState<AdminPromotionCodeCreateDialog> createState() =>
      _AdminPromotionCodeCreateDialogState();
}

class _AdminPromotionCodeCreateDialogState
    extends ConsumerState<AdminPromotionCodeCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _maxRedemptions = TextEditingController();
  DateTime? _expiresAt;
  bool _firstTimeTransaction = false;
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    _maxRedemptions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.adminCouponsAddCodeTitle(widget.coupon.name)),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_-]')),
                    LengthLimitingTextInputFormatter(32),
                  ],
                  decoration: InputDecoration(
                    labelText: l.adminCouponsCodeField,
                    hintText: 'VERANO2026',
                    helperText: l.adminCouponsCodeFieldHelp,
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.length < 3) return l.adminCouponsErrCodeTooShort;
                    if (!RegExp(r'^[A-Za-z0-9_-]{3,32}$').hasMatch(t)) {
                      return l.adminCouponsErrCodeInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
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
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: l.adminCouponsCodeFieldExpiresAt,
                    suffixIcon: _expiresAt == null
                        ? IconButton(
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: _pickDate,
                          )
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _expiresAt = null),
                          ),
                  ),
                  child: InkWell(
                    onTap: _pickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _expiresAt == null
                            ? l.adminCouponsNoExpiry
                            : '${_expiresAt!.year}-${_expiresAt!.month.toString().padLeft(2, '0')}-${_expiresAt!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l.adminCouponsFieldFirstTimeTx),
                  subtitle: Text(l.adminCouponsFieldFirstTimeTxHelp),
                  value: _firstTimeTransaction,
                  onChanged: (v) =>
                      setState(() => _firstTimeTransaction = v ?? false),
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _onSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l = context.l10n;
    setState(() => _saving = true);
    final ds = ref.read(adminCouponsDataSourceProvider);
    try {
      await ds.createPromotionCode(
        couponId: widget.coupon.id,
        code: _code.text.trim(),
        maxRedemptions: _maxRedemptions.text.trim().isEmpty
            ? null
            : int.parse(_maxRedemptions.text.trim()),
        expiresAt: _expiresAt,
        firstTimeTransaction: _firstTimeTransaction,
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
