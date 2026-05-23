// ============================================================================
// AI providers · Superadmin UI (Fase 0)
// ----------------------------------------------------------------------------
// `/admin/ai-providers` (capability `manage_ai`). Registro de proveedores de
// IA: activar/desactivar, prioridad, modelo y base_url; y gestión de API keys
// (añadir / activar-desactivar / borrar, con preview enmascarada ••••last4) +
// botón Probar (mini-llamada real al proveedor). Las keys nunca se muestran.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/ai_providers_providers.dart';
import '../../data/ai_admin_datasource.dart';
import '../../domain/ai_provider.dart';

class AdminAiProvidersPage extends StatelessWidget {
  const AdminAiProvidersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.admin),
        ),
        title: Text(l.adminAiProvidersTitle),
      ),
      body: const AdminAiProvidersView(),
    );
  }
}

/// Cuerpo reutilizable (página completa o embebido en el master-detail).
class AdminAiProvidersView extends ConsumerStatefulWidget {
  const AdminAiProvidersView({this.embedded = false, super.key});

  final bool embedded;

  @override
  ConsumerState<AdminAiProvidersView> createState() =>
      _AdminAiProvidersViewState();
}

class _AdminAiProvidersViewState extends ConsumerState<AdminAiProvidersView> {
  bool _working = false;

  AiAdminDataSource get _ds => ref.read(aiAdminDataSourceProvider);

  void _refresh() => ref.invalidate(aiAdminListProvider);

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    if (_working) return;
    setState(() => _working = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await action();
      _refresh();
      messenger.showSnackBar(SnackBar(content: Text(okMsg)));
    } on AiAdminException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.aiLoadError} (${e.code})'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text(l.aiLoadError),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _testProvider(AiProvider p) async {
    if (_working) return;
    setState(() => _working = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    final result = await _ds.test(p.id);
    if (!mounted) return;
    setState(() => _working = false);
    if (result.ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l.aiTestOk} · ${result.model ?? p.slug}'),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.aiTestFailed}: ${result.detail ?? '?'}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(aiAdminListProvider);

    final content = async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: AppLoadingState(),
      ),
      error: (e, _) => AppErrorState(
        message: l.aiLoadError,
        detail: e.toString(),
        onRetry: _refresh,
        retryLabel: l.actionRetry,
      ),
      data: (data) {
        final sorted = [...data.providers]
          ..sort((a, b) => a.priority.compareTo(b.priority));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.aiProvidersIntro,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            AppSpacing.gapMd,
            for (final p in sorted) ...[
              _providerCard(p, data.credentialsFor(p.id)),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: content,
      );
    }

    return Scaffold(
      // Caso página completa fuera del shell (no debería ocurrir, pero por
      // robustez damos un fondo).
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: l.adminAiProvidersTitle,
                  subtitle: l.adminAiProvidersHint,
                ),
                AppSpacing.gapMd,
                content,
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _providerCard(AiProvider p, List<AiCredential> creds) {
    final l = context.l10n;
    final scheme = context.colors;
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.displayName,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    PremiumBadge(
                      label: p.isFree ? l.aiTierFree : l.aiTierPaid,
                      variant: p.isFree
                          ? PremiumBadgeVariant.success
                          : PremiumBadgeVariant.info,
                      dense: true,
                    ),
                  ],
                ),
              ),
              Switch(
                value: p.enabled,
                onChanged: _working
                    ? null
                    : (v) => _run(
                          () => _ds.saveProvider(id: p.id, enabled: v),
                          l.aiSaved,
                        ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${l.aiProviderModelLabel}: ${p.defaultModel ?? l.aiProviderNoModel}'
            '   ·   ${l.aiProviderPriorityLabel}: ${p.priority}',
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          AppSpacing.gapSm,
          // Acciones de proveedor.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                onPressed: _working ? null : () => _editProvider(p),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(l.aiProviderEditTitle),
              ),
              OutlinedButton.icon(
                onPressed: _working ? null : () => _testProvider(p),
                icon: const Icon(Icons.bolt_outlined, size: 16),
                label: Text(l.aiTest),
              ),
              FilledButton.tonalIcon(
                onPressed: _working ? null : () => _addKey(p),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l.aiAddKey),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          Text(
            l.aiKeysLabel,
            style: context.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          AppSpacing.gapXs,
          if (creds.isEmpty)
            Text(
              l.aiNoKeys,
              style: context.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final c in creds) _credentialRow(c),
        ],
      ),
    );
  }

  Widget _credentialRow(AiCredential c) {
    final l = context.l10n;
    final scheme = context.colors;
    final status = !c.enabled
        ? l.aiKeyDisabled
        : (c.onCooldown ? l.aiKeyOnCooldown : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.vpn_key_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${(c.label?.isNotEmpty ?? false) ? '${c.label} · ' : ''}'
              '••••${c.keyLast4 ?? '????'}'
              '${status != null ? '  ($status)' : ''}',
              style: context.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Switch(
            value: c.enabled,
            onChanged: _working
                ? null
                : (v) => _run(
                      () => _ds.updateCredential(
                        id: c.id,
                        enabled: v,
                        clearCooldown: v,
                      ),
                      l.aiSaved,
                    ),
          ),
          IconButton(
            tooltip: l.aiDeleteCta,
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: _working ? null : () => _deleteKey(c),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── Diálogos ───────────────────────────

  Future<void> _addKey(AiProvider p) async {
    final addedMsg = context.l10n.aiKeyAdded;
    final result = await showDialog<({String? label, String apiKey})>(
      context: context,
      builder: (_) => _AddKeyDialog(providerName: p.displayName),
    );
    if (result == null) return;
    await _run(
      () => _ds.addCredential(
        providerId: p.id,
        apiKey: result.apiKey,
        label: result.label,
      ),
      addedMsg,
    );
  }

  Future<void> _deleteKey(AiCredential c) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.aiDeleteKeyTitle),
        content: Text(l.aiDeleteKeyBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.aiDeleteCta),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _ds.deleteCredential(c.id), l.aiKeyDeleted);
  }

  Future<void> _editProvider(AiProvider p) async {
    final savedMsg = context.l10n.aiSaved;
    final result =
        await showDialog<({int priority, String model, String baseUrl})>(
      context: context,
      builder: (_) => _EditProviderDialog(provider: p),
    );
    if (result == null) return;
    await _run(
      () => _ds.saveProvider(
        id: p.id,
        priority: result.priority,
        defaultModel: result.model,
        baseUrl: result.baseUrl.isEmpty ? null : result.baseUrl,
      ),
      savedMsg,
    );
  }
}

/// Diálogo para añadir una API key (etiqueta opcional + key obligatoria).
class _AddKeyDialog extends StatefulWidget {
  const _AddKeyDialog({required this.providerName});
  final String providerName;

  @override
  State<_AddKeyDialog> createState() => _AddKeyDialogState();
}

class _AddKeyDialogState extends State<_AddKeyDialog> {
  late final TextEditingController _label;
  late final TextEditingController _key;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController();
    _key = TextEditingController();
  }

  @override
  void dispose() {
    _label.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text('${l.aiAddKeyTitle} · ${widget.providerName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _label,
            label: l.aiKeyLabelField,
            prefixIcon: Icons.label_outline,
          ),
          AppTextField(
            controller: _key,
            label: l.aiApiKeyField,
            prefixIcon: Icons.vpn_key_outlined,
            isPassword: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            final key = _key.text.trim();
            if (key.length < 8) return;
            Navigator.of(context).pop(
              (
                label: _label.text.trim().isEmpty ? null : _label.text.trim(),
                apiKey: key,
              ),
            );
          },
          child: Text(l.actionSave),
        ),
      ],
    );
  }
}

/// Diálogo para editar prioridad / modelo / base_url de un proveedor.
class _EditProviderDialog extends StatefulWidget {
  const _EditProviderDialog({required this.provider});
  final AiProvider provider;

  @override
  State<_EditProviderDialog> createState() => _EditProviderDialogState();
}

class _EditProviderDialogState extends State<_EditProviderDialog> {
  late final TextEditingController _priority;
  late final TextEditingController _model;
  late final TextEditingController _baseUrl;

  @override
  void initState() {
    super.initState();
    _priority = TextEditingController(text: '${widget.provider.priority}');
    _model = TextEditingController(text: widget.provider.defaultModel ?? '');
    _baseUrl = TextEditingController(text: widget.provider.baseUrl ?? '');
  }

  @override
  void dispose() {
    _priority.dispose();
    _model.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text('${l.aiProviderEditTitle} · ${widget.provider.displayName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _priority,
            label: l.aiProviderPriorityLabel,
            prefixIcon: Icons.low_priority_outlined,
            keyboardType: TextInputType.number,
          ),
          AppTextField(
            controller: _model,
            label: l.aiProviderModelLabel,
            prefixIcon: Icons.memory_outlined,
          ),
          AppTextField(
            controller: _baseUrl,
            label: l.aiProviderBaseUrlLabel,
            prefixIcon: Icons.link_outlined,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            final prio =
                int.tryParse(_priority.text.trim()) ?? widget.provider.priority;
            Navigator.of(context).pop(
              (
                priority: prio,
                model: _model.text.trim(),
                baseUrl: _baseUrl.text.trim(),
              ),
            );
          },
          child: Text(l.actionSave),
        ),
      ],
    );
  }
}
