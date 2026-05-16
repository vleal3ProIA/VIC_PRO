import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../application/admin_plans_providers.dart';
import '../../data/admin_plans_datasource.dart';
import '../../domain/plan.dart';

/// Dialog "Cambiar precio del plan X". Stripe Prices son inmutables: este
/// flujo crea Prices nuevos y opcionalmente migra las suscripciones
/// existentes según la estrategia elegida.
///
/// El dialog hace un `preview` al abrirse para mostrar cuántas
/// suscripciones activas hay y poder advertir del impacto antes de
/// aplicar. Pop con `true` si el cambio se aplicó.
class AdminPlanPriceChangeDialog extends ConsumerStatefulWidget {
  const AdminPlanPriceChangeDialog({required this.plan, super.key});

  final Plan plan;

  @override
  ConsumerState<AdminPlanPriceChangeDialog> createState() =>
      _AdminPlanPriceChangeDialogState();
}

class _AdminPlanPriceChangeDialogState
    extends ConsumerState<AdminPlanPriceChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _monthly;
  late final TextEditingController _yearly;
  PriceMigrationStrategy _strategy = PriceMigrationStrategy.grandfather;

  /// Resultado del `preview` al abrir el dialog.
  int? _activeSubsCount;
  bool _loadingPreview = true;
  String? _previewError;

  bool _applying = false;

  @override
  void initState() {
    super.initState();
    // Pre-rellenamos con los precios actuales (en €/$ con 2 decimales)
    // para que el admin solo tenga que tocar los que quiera cambiar.
    _monthly = TextEditingController(
      text: widget.plan.priceMonthlyCents == null
          ? ''
          : (widget.plan.priceMonthlyCents! / 100).toStringAsFixed(2),
    );
    _yearly = TextEditingController(
      text: widget.plan.priceYearlyCents == null
          ? ''
          : (widget.plan.priceYearlyCents! / 100).toStringAsFixed(2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
  }

  @override
  void dispose() {
    _monthly.dispose();
    _yearly.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    try {
      final res = await ref
          .read(adminPlansDataSourceProvider)
          .previewPriceChange(planId: widget.plan.id);
      if (!mounted) return;
      setState(() {
        _activeSubsCount = res.activeSubscriptionsCount;
        _loadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewError = e.toString();
        _loadingPreview = false;
      });
    }
  }

  /// Parsea el campo (acepta `,` y `.`) y devuelve cents enteros.
  /// Devuelve `null` si el campo está vacío, "no cambia".
  int? _parseToCents(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    if (n == null) return null;
    return (n * 100).round();
  }

  bool _hasAnyChange() {
    final newMonthly = _parseToCents(_monthly.text);
    final newYearly = _parseToCents(_yearly.text);
    final changedMonthly = newMonthly != null &&
        newMonthly != widget.plan.priceMonthlyCents;
    final changedYearly = newYearly != null &&
        newYearly != widget.plan.priceYearlyCents;
    return changedMonthly || changedYearly;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.adminPlansPriceTitle(widget.plan.name)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ImpactBanner(
                  loading: _loadingPreview,
                  count: _activeSubsCount,
                  error: _previewError,
                ),
                const SizedBox(height: 16),
                Text(
                  l.adminPlansPriceFieldsSection,
                  style: context.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _PriceField(
                        controller: _monthly,
                        label: l.adminPlansPriceMonthly,
                        currency: widget.plan.currency,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PriceField(
                        controller: _yearly,
                        label: l.adminPlansPriceYearly,
                        currency: widget.plan.currency,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l.adminPlansPriceHelp,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l.adminPlansPriceStrategySection,
                  style: context.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                RadioGroup<PriceMigrationStrategy>(
                  groupValue: _strategy,
                  onChanged: (v) =>
                      setState(() => _strategy = v ?? _strategy),
                  child: Column(
                    children: [
                      _StrategyTile(
                        value: PriceMigrationStrategy.grandfather,
                        title: l.adminPlansPriceStrategyGrandfather,
                        subtitle: l.adminPlansPriceStrategyGrandfatherHelp,
                      ),
                      _StrategyTile(
                        value: PriceMigrationStrategy.nextPeriod,
                        title: l.adminPlansPriceStrategyNextPeriod,
                        subtitle: l.adminPlansPriceStrategyNextPeriodHelp,
                      ),
                      _StrategyTile(
                        value: PriceMigrationStrategy.immediate,
                        title: l.adminPlansPriceStrategyImmediate,
                        subtitle: l.adminPlansPriceStrategyImmediateHelp,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _applying ? null : () => Navigator.pop(context, false),
          child: Text(l.actionCancel),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.errorContainer,
            foregroundColor: context.colors.onErrorContainer,
          ),
          onPressed: _applying || _loadingPreview || !_hasAnyChange()
              ? null
              : _onApply,
          child: _applying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.adminPlansPriceApply),
        ),
      ],
    );
  }

  Future<void> _onApply() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l = context.l10n;
    final newMonthly = _parseToCents(_monthly.text);
    final newYearly = _parseToCents(_yearly.text);
    final sendMonthly = newMonthly != null &&
        newMonthly != widget.plan.priceMonthlyCents
        ? newMonthly
        : null;
    final sendYearly = newYearly != null &&
        newYearly != widget.plan.priceYearlyCents
        ? newYearly
        : null;
    if (sendMonthly == null && sendYearly == null) return;

    // Confirmación final si hay subscriptores afectados y la estrategia
    // los va a tocar (no grandfather).
    final affecting = _strategy != PriceMigrationStrategy.grandfather &&
        (_activeSubsCount ?? 0) > 0;
    if (affecting) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.adminPlansPriceConfirmTitle),
          content: Text(
            l.adminPlansPriceConfirmBody(
              _activeSubsCount!,
              switch (_strategy) {
                PriceMigrationStrategy.nextPeriod =>
                  l.adminPlansPriceStrategyNextPeriod,
                PriceMigrationStrategy.immediate =>
                  l.adminPlansPriceStrategyImmediate,
                _ => '',
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.adminPlansPriceApply),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _applying = true);
    try {
      final res = await ref.read(adminPlansDataSourceProvider).applyPriceChange(
            planId: widget.plan.id,
            newMonthlyCents: sendMonthly,
            newYearlyCents: sendYearly,
            migrationStrategy: _strategy,
          );
      if (!mounted) return;
      if (res.errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.adminPlansPricePartial(res.migratedCount, res.errors.length),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.adminPlansPriceApplied(res.migratedCount))),
        );
      }
      Navigator.pop(context, true);
    } on AdminPlanException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.adminPlansPriceError} (${e.code})')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminPlansPriceError)),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }
}

class _ImpactBanner extends StatelessWidget {
  const _ImpactBanner({
    required this.loading,
    required this.count,
    required this.error,
  });
  final bool loading;
  final int? count;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Color bg;
    IconData icon;
    String text;
    if (loading) {
      return const LinearProgressIndicator();
    }
    if (error != null) {
      bg = context.colors.errorContainer;
      icon = Icons.error_outline;
      text = l.adminPlansPricePreviewError;
    } else if ((count ?? 0) == 0) {
      bg = context.colors.surfaceContainerHigh;
      icon = Icons.info_outline;
      text = l.adminPlansPriceNoSubs;
    } else {
      bg = context.colors.tertiaryContainer;
      icon = Icons.warning_amber_outlined;
      text = l.adminPlansPriceImpact(count!);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: context.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.label,
    required this.currency,
  });
  final TextEditingController controller;
  final String label;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: currency,
      ),
      validator: (v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return null;
        final n = double.tryParse(t.replaceAll(',', '.'));
        if (n == null || n <= 0) return context.l10n.adminPlansPriceInvalid;
        return null;
      },
    );
  }
}

/// Item de un grupo de radios — espera un `RadioGroup<PriceMigrationStrategy>`
/// ancestro que provee `groupValue` y `onChanged` (API nueva post-Flutter
/// 3.32).
class _StrategyTile extends StatelessWidget {
  const _StrategyTile({
    required this.value,
    required this.title,
    required this.subtitle,
  });
  final PriceMigrationStrategy value;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<PriceMigrationStrategy>(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
    );
  }
}
