import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/promotion_code_providers.dart';
import '../../data/promotion_code_validator.dart';

/// Widget colapsable "¿Tienes un código promocional?" que aparece encima
/// del catálogo de planes. Al validar OK, persiste el descuento en
/// `appliedPromotionCodeProvider` para que las cards lo apliquen al precio
/// y el botón de upgrade lo pase a Stripe Checkout.
class PromotionCodeField extends ConsumerStatefulWidget {
  const PromotionCodeField({super.key});

  @override
  ConsumerState<PromotionCodeField> createState() => _PromotionCodeFieldState();
}

class _PromotionCodeFieldState extends ConsumerState<PromotionCodeField> {
  final _controller = TextEditingController();
  bool _expanded = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final applied = ref.watch(appliedPromotionCodeProvider);

    // Si hay un código aplicado, mostramos el resumen + botón "Quitar".
    if (applied != null) {
      final discountStr = applied.isPercent
          ? '−${applied.percentOff!.toStringAsFixed(0)}%'
          : '−${((applied.amountOffCents ?? 0) / 100).toStringAsFixed(2)} ${_symbol(applied.currency)}';
      return Card(
        color: context.colors.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.local_offer,
                color: context.colors.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: applied.code,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: '  •  '),
                      TextSpan(text: discountStr),
                      TextSpan(
                        text: '  ${_durationText(l, applied.duration, applied.durationInMonths)}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSecondaryContainer
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(color: context.colors.onSecondaryContainer),
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.read(appliedPromotionCodeProvider.notifier).state = null;
                  setState(() {
                    _controller.clear();
                    _error = null;
                    _expanded = false;
                  });
                },
                child: Text(l.plansPromoRemove),
              ),
            ],
          ),
        ),
      );
    }

    // Sin código aplicado: colapsable.
    if (!_expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.local_offer_outlined, size: 18),
          label: Text(l.plansPromoToggle),
          onPressed: () => setState(() => _expanded = true),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l.plansPromoFieldLabel,
                  hintText: 'VERANO2026',
                  errorText: _error,
                  isDense: true,
                ),
                onSubmitted: (_) => _onApply(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _onApply,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.plansPromoApply),
            ),
            IconButton(
              tooltip: l.actionCancel,
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _expanded = false;
                  _controller.clear();
                  _error = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onApply() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(promotionCodeValidatorProvider)
          .validate(code: raw);
      if (!mounted) return;
      switch (result) {
        case PromotionCodeValid(:final applied):
          ref.read(appliedPromotionCodeProvider.notifier).state = applied;
          setState(() => _expanded = false);
        case PromotionCodeInvalid(:final reason):
          setState(() => _error = _reasonText(context.l10n, reason));
      }
    } on PromotionCodeValidatorException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.code == 'rate_limited'
            ? context.l10n.plansPromoRateLimited
            : context.l10n.plansPromoInvalid,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.l10n.plansPromoInvalid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _reasonText(AppLocalizations l, String reason) {
    switch (reason) {
      case 'not_applicable_to_plan':
        return l.plansPromoNotForPlan;
      case 'not_synced':
      case 'not_found_or_expired':
      default:
        return l.plansPromoInvalid;
    }
  }

  String _durationText(AppLocalizations l, String duration, int? months) {
    switch (duration) {
      case 'forever':
        return l.plansPromoDurationForever;
      case 'repeating':
        return l.plansPromoDurationRepeatingN(months ?? 0);
      case 'once':
      default:
        return l.plansPromoDurationOnce;
    }
  }

  String _symbol(String? c) {
    switch (c) {
      case 'USD':
        return r'$';
      case 'GBP':
        return '£';
      case 'EUR':
      default:
        return '€';
    }
  }
}
