import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/feature_flags_providers.dart';
import '../../data/feature_flags_datasource.dart';
import '../../domain/feature_flag.dart';

/// Pantalla `/admin/flags` — gestión de feature flags (solo admin global).
///
/// Permite:
///   - Toggle `enabled` global de un flag.
///   - Ajustar `rollout_percentage` (0-100) — el % de usuarios donde se
///     considera activo aleatoriamente (determinista por user_id+key).
///   - Ver `source` predominante en producción (necesita observabilidad
///     real para datos — esta UI solo expone la config).
///
/// Cuando un flag tiene rollout > 0 y < 100, la fila lo indica con un
/// chip "rollout".
class AdminFlagsPage extends ConsumerWidget {
  const AdminFlagsPage({super.key});

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
        title: Text(l.adminFlagsTitle),
      ),
      body: const AdminFlagsView(),
    );
  }
}

/// Cuerpo de la gestión de feature flags (sin Scaffold). Reutilizable como
/// página completa o embebido en el master-detail de Administración.
class AdminFlagsView extends ConsumerWidget {
  const AdminFlagsView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Admin).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final defsAsync = ref.watch(featureFlagDefinitionsProvider);

    final body = defsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            l.adminFlagsError,
            style: TextStyle(color: context.colors.error),
          ),
        ),
      ),
      data: (defs) {
        if (defs.isEmpty) {
          return Center(child: Text(l.adminFlagsEmpty));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          shrinkWrap: embedded,
          physics: embedded ? const NeverScrollableScrollPhysics() : null,
          itemCount: defs.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) => _FlagCard(definition: defs[i]),
        );
      },
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
        child: Column(
          mainAxisSize: embedded ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // Acción refresh (antes en el AppBar).
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: l.actionRetry,
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.invalidate(featureFlagDefinitionsProvider),
                ),
              ),
            ),
            if (embedded) body else Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _FlagCard extends ConsumerStatefulWidget {
  const _FlagCard({required this.definition});
  final FeatureFlagDefinition definition;
  @override
  ConsumerState<_FlagCard> createState() => _FlagCardState();
}

class _FlagCardState extends ConsumerState<_FlagCard> {
  late bool _enabled;
  late double _rollout;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.definition.enabled;
    _rollout = widget.definition.rolloutPercentage.toDouble();
  }

  /// Si el provider entrega una definición distinta (p.ej. tras un refresh
  /// que confirma el valor real en BD), resincronizamos el estado local
  /// salvo que el usuario esté manipulando algo (no estamos `_busy`). Esto
  /// evita que el Switch quede "mintiendo" tras un guardado fallido.
  @override
  void didUpdateWidget(_FlagCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy && widget.definition.enabled != _enabled) {
      _enabled = widget.definition.enabled;
    }
    if (!_busy &&
        widget.definition.rolloutPercentage.toDouble() != _rollout) {
      _rollout = widget.definition.rolloutPercentage.toDouble();
    }
  }

  Future<void> _save({bool? enabled, int? rollout}) async {
    setState(() => _busy = true);
    final ds = ref.read(featureFlagsDataSourceProvider);
    try {
      await ds.update(
        key: widget.definition.key,
        enabled: enabled,
        rolloutPercentage: rollout,
      );
      ref
        ..invalidate(featureFlagDefinitionsProvider)
        ..invalidate(myFeatureFlagsProvider);
      if (mounted) context.showSnack(context.l10n.settingsSaved);
    } on FeatureFlagsWriteDenied {
      // RLS rechazó: revertimos el estado local al de la BD para que el
      // Switch deje de mostrar el valor "fantasma" no persistido.
      if (!mounted) return;
      setState(() {
        if (enabled != null) _enabled = widget.definition.enabled;
        if (rollout != null) {
          _rollout = widget.definition.rolloutPercentage.toDouble();
        }
      });
      context.showSnack(context.l10n.adminFlagsErrorDenied, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (enabled != null) _enabled = widget.definition.enabled;
        if (rollout != null) {
          _rollout = widget.definition.rolloutPercentage.toDouble();
        }
      });
      context.showSnack(context.l10n.adminFlagsError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = widget.definition;
    return PremiumCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.key,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (d.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        d.description!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: _busy
                    ? null
                    : (v) {
                        setState(() => _enabled = v);
                        _save(enabled: v);
                      },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.percent,
                size: 16,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 60,
                child: Text(
                  l.adminFlagsRollout('${_rollout.toInt()}'),
                  style: context.textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _rollout,
                  max: 100,
                  divisions: 20,
                  label: '${_rollout.toInt()}%',
                  onChanged: _busy ? null : (v) => setState(() => _rollout = v),
                  onChangeEnd: (v) => _save(rollout: v.toInt()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
