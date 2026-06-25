// ============================================================================
// AI quotas · Superadmin UI (migracion 0105)
// ----------------------------------------------------------------------------
// `/admin/ai-quotas` (capability `manage_ai`). Edita el cap diario de llamadas
// a IA por plan (free/pro/max) y gestiona overrides por usuario (VIPs o
// castigados por abuso). Sirve para cortar la sangria cuando un user genera
// 500€/noche de Gemini.
//
// Defensa server-side: RLS en `ai_quotas` + `ai_user_overrides` y las RPCs
// `admin_set_ai_quota` / `admin_set_user_override` validan `is_admin()`.
// La pagina solo es una UI sobre esas RPCs.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_text_field.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────── Domain types ────────────────────────────────────────

/// Cuota IA configurada para un plan (`free`/`pro`/`max`).
class AiPlanQuota {
  const AiPlanQuota({required this.planSlug, required this.dailyCallLimit});
  final String planSlug;
  final int dailyCallLimit;
}

/// Override de cuota IA para un usuario concreto. Prevalece sobre el plan.
class AiUserOverride {
  const AiUserOverride({
    required this.userId,
    required this.dailyCallLimit,
    this.reason,
    this.userEmail,
    this.createdBy,
    this.updatedAt,
  });
  final String userId;
  final int dailyCallLimit;
  final String? reason;
  final String? userEmail;
  final String? createdBy;
  final DateTime? updatedAt;
}

// ─────────────────── Data source (Supabase) ──────────────────────────────

/// Lee/escribe `ai_quotas` y `ai_user_overrides` via RPCs admin_*.
class AiQuotasDataSource {
  const AiQuotasDataSource(this._client);
  final SupabaseClient _client;

  /// Lista cuotas por plan. Devuelve filas de `ai_quotas` (RLS permite
  /// SELECT a authenticated, por lo que el admin las ve sin RPC).
  Future<List<AiPlanQuota>> listPlanQuotas() async {
    final data = await _client
        .from('ai_quotas')
        .select('plan_slug, daily_call_limit')
        .order('daily_call_limit');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(
          (m) => AiPlanQuota(
            planSlug: m['plan_slug'] as String,
            dailyCallLimit: (m['daily_call_limit'] as num).toInt(),
          ),
        )
        .toList(growable: false);
  }

  /// Lista overrides por usuario (paginado). Incluye email join a auth.users
  /// via la vista admin_users (si existe) o directamente. Aqui usamos un
  /// SELECT simple a `ai_user_overrides`; la UI hace lookup de email aparte.
  /// 50 por pagina por defecto (cap razonable, no esperamos miles).
  Future<List<AiUserOverride>> listUserOverrides({
    int limit = 50,
    int offset = 0,
  }) async {
    final safe = limit.clamp(1, 200);
    final data = await _client
        .from('ai_user_overrides')
        .select('user_id, daily_call_limit, reason, created_by, updated_at')
        .order('updated_at', ascending: false)
        .range(offset, offset + safe - 1);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(
          (m) => AiUserOverride(
            userId: m['user_id'] as String,
            dailyCallLimit: (m['daily_call_limit'] as num).toInt(),
            reason: m['reason'] as String?,
            createdBy: m['created_by'] as String?,
            updatedAt: DateTime.tryParse(
              (m['updated_at'] ?? '').toString(),
            ),
          ),
        )
        .toList(growable: false);
  }

  /// Actualiza el cap del plan via RPC `admin_set_ai_quota` (security definer
  /// con check `is_admin()`).
  Future<void> setPlanQuota(String planSlug, int limit) async {
    await _client.rpc<dynamic>(
      'admin_set_ai_quota',
      params: {'p_plan_slug': planSlug, 'p_limit': limit},
    );
  }

  /// Fija (o quita con `limit=-1`) el override de un usuario via RPC
  /// `admin_set_user_override`.
  Future<void> setUserOverride({
    required String userId,
    required int limit,
    String? reason,
  }) async {
    await _client.rpc<dynamic>(
      'admin_set_user_override',
      params: {
        'p_user_id': userId,
        'p_limit': limit,
        'p_reason': reason,
      },
    );
  }

  /// Busca un user por email exacto en `auth.users` (via RPC admin existente
  /// `admin_list_users` o similar). Si tu proyecto no la tiene, devolvemos
  /// null y la UI pide el UUID directamente.
  Future<String?> findUserIdByEmail(String email) async {
    try {
      // Intento 1: RPC ya existente del modulo admin_users.
      final res = await _client.rpc<dynamic>(
        'admin_find_user_by_email',
        params: {'p_email': email},
      );
      if (res is String && res.isNotEmpty) return res;
      if (res is List && res.isNotEmpty) {
        final first = res.first;
        if (first is String) return first;
        if (first is Map && first['id'] is String) return first['id'] as String;
      }
    } catch (_) {
      // RPC inexistente o sin permisos; degradamos a null.
    }
    return null;
  }
}

final aiQuotasDataSourceProvider = Provider<AiQuotasDataSource>((ref) {
  return AiQuotasDataSource(ref.watch(supabaseClientProvider));
});

final aiPlanQuotasProvider = FutureProvider<List<AiPlanQuota>>((ref) {
  return ref.watch(aiQuotasDataSourceProvider).listPlanQuotas();
});

/// Estado de paginacion para la lista de overrides.
class _OverridesPage {
  const _OverridesPage(this.offset, this.limit);
  final int offset;
  final int limit;
}

final aiOverridesPageProvider =
    StateProvider<_OverridesPage>((_) => const _OverridesPage(0, 50));

final aiUserOverridesProvider =
    FutureProvider<List<AiUserOverride>>((ref) async {
  final page = ref.watch(aiOverridesPageProvider);
  return ref
      .watch(aiQuotasDataSourceProvider)
      .listUserOverrides(limit: page.limit, offset: page.offset);
});

// ─────────────────── Page ─────────────────────────────────────────────────

class AdminAiQuotasPage extends StatelessWidget {
  const AdminAiQuotasPage({super.key});

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
        title: Text(l.adminAiQuotasTitle),
      ),
      body: const AdminAiQuotasView(),
    );
  }
}

/// Cuerpo reutilizable (pagina completa o embebido en el master-detail).
class AdminAiQuotasView extends ConsumerStatefulWidget {
  const AdminAiQuotasView({this.embedded = false, super.key});
  final bool embedded;

  @override
  ConsumerState<AdminAiQuotasView> createState() => _AdminAiQuotasViewState();
}

class _AdminAiQuotasViewState extends ConsumerState<AdminAiQuotasView> {
  bool _working = false;

  AiQuotasDataSource get _ds => ref.read(aiQuotasDataSourceProvider);

  void _refresh() {
    ref
      ..invalidate(aiPlanQuotasProvider)
      ..invalidate(aiUserOverridesProvider);
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    if (_working) return;
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await action();
      _refresh();
      messenger.showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text(e.toString()),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plans = ref.watch(aiPlanQuotasProvider);
    final overrides = ref.watch(aiUserOverridesProvider);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.adminAiQuotasSubtitle,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        AppSpacing.gapLg,
        SectionHeader(title: l.adminAiQuotasPerPlan, compact: true),
        AppSpacing.gapMd,
        plans.when(
          loading: () => const AppLoadingState(),
          error: (e, _) => AppErrorState(
            message: e.toString(),
            onRetry: _refresh,
            retryLabel: l.actionRetry,
          ),
          data: (data) {
            if (data.isEmpty) {
              return PremiumCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(l.adminAiQuotasNoPlans),
              );
            }
            return Column(
              children: [
                for (final q in data) ...[
                  _PlanQuotaCard(
                    quota: q,
                    working: _working,
                    onSave: (newLimit) => _run(
                      () => _ds.setPlanQuota(q.planSlug, newLimit),
                      l.adminAiQuotaSaveOk,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
        AppSpacing.gapXl,
        SectionHeader(title: l.adminAiQuotasOverrides, compact: true),
        AppSpacing.gapMd,
        _AddOverrideCard(
          working: _working,
          onAdd: ({
            required String userId,
            required int limit,
            String? reason,
          }) =>
              _run(
            () => _ds.setUserOverride(
              userId: userId,
              limit: limit,
              reason: reason,
            ),
            l.adminAiQuotaSaveOk,
          ),
          findUserId: _ds.findUserIdByEmail,
        ),
        const SizedBox(height: AppSpacing.md),
        overrides.when(
          loading: () => const AppLoadingState(),
          error: (e, _) => AppErrorState(
            message: e.toString(),
            onRetry: _refresh,
            retryLabel: l.actionRetry,
          ),
          data: (rows) => _OverridesList(
            rows: rows,
            working: _working,
            onRemove: (userId) => _run(
              () => _ds.setUserOverride(userId: userId, limit: -1),
              l.adminAiQuotaSaveOk,
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: content,
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: l.adminAiQuotasTitle,
                subtitle: l.adminAiQuotasSubtitle,
              ),
              AppSpacing.gapMd,
              content,
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card con slider + numero editable para la cuota de UN plan.
class _PlanQuotaCard extends StatefulWidget {
  const _PlanQuotaCard({
    required this.quota,
    required this.working,
    required this.onSave,
  });
  final AiPlanQuota quota;
  final bool working;
  final ValueChanged<int> onSave;

  @override
  State<_PlanQuotaCard> createState() => _PlanQuotaCardState();
}

class _PlanQuotaCardState extends State<_PlanQuotaCard> {
  late int _value;
  late final TextEditingController _ctrl;

  static const int _maxLimit = 5000;

  @override
  void initState() {
    super.initState();
    _value = widget.quota.dailyCallLimit;
    _ctrl = TextEditingController(text: '$_value');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _setValue(int v) {
    final clamped = v.clamp(0, _maxLimit);
    setState(() {
      _value = clamped;
      _ctrl.text = '$clamped';
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final dirty = _value != widget.quota.dailyCallLimit;
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.quota.planSlug.toUpperCase(),
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 110,
                child: AppTextField(
                  controller: _ctrl,
                  label: l.adminAiQuotaLimitField,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) {
                    final n = int.tryParse(v.trim()) ?? _value;
                    setState(() => _value = n.clamp(0, _maxLimit));
                  },
                ),
              ),
            ],
          ),
          Slider(
            value: _value.toDouble().clamp(0, _maxLimit.toDouble()),
            min: 0,
            max: _maxLimit.toDouble(),
            divisions: 100,
            label: '$_value',
            onChanged: widget.working ? null : (v) => _setValue(v.round()),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: PremiumButton(
              label: l.actionSave,
              leadingIcon: Icons.save_outlined,
              onPressed: (widget.working || !dirty)
                  ? null
                  : () => widget.onSave(_value),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formulario para anyadir un override por usuario (email + limit + reason).
class _AddOverrideCard extends StatefulWidget {
  const _AddOverrideCard({
    required this.working,
    required this.onAdd,
    required this.findUserId,
  });
  final bool working;
  final void Function({
    required String userId,
    required int limit,
    String? reason,
  }) onAdd;
  final Future<String?> Function(String email) findUserId;

  @override
  State<_AddOverrideCard> createState() => _AddOverrideCardState();
}

class _AddOverrideCardState extends State<_AddOverrideCard> {
  final _email = TextEditingController();
  final _userId = TextEditingController();
  final _reason = TextEditingController();
  int _limit = 100;
  bool _lookingUp = false;
  String? _lookupError;
  static const int _maxLimit = 5000;

  @override
  void dispose() {
    _email.dispose();
    _userId.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _resolveEmail() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _lookingUp = true;
      _lookupError = null;
    });
    final id = await widget.findUserId(email);
    if (!mounted) return;
    setState(() {
      _lookingUp = false;
      if (id == null) {
        _lookupError = context.l10n.adminAiQuotaUserNotFound;
      } else {
        _userId.text = id;
      }
    });
  }

  void _submit() {
    final id = _userId.text.trim();
    if (id.isEmpty || _limit < 0) return;
    final reason = _reason.text.trim();
    widget.onAdd(
      userId: id,
      limit: _limit,
      reason: reason.isEmpty ? null : reason,
    );
    _email.clear();
    _userId.clear();
    _reason.clear();
    setState(() {
      _limit = 100;
      _lookupError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.adminAiQuotaAddOverride,
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          AppSpacing.gapSm,
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _email,
                  label: l.adminAiQuotaEmailField,
                  prefixIcon: Icons.mail_outline,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed:
                    (widget.working || _lookingUp) ? null : _resolveEmail,
                icon: const Icon(Icons.search, size: 16),
                label: Text(l.adminAiQuotaLookup),
              ),
            ],
          ),
          if (_lookupError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _lookupError!,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
          AppSpacing.gapXs,
          AppTextField(
            controller: _userId,
            label: l.adminAiQuotaUserIdField,
            prefixIcon: Icons.fingerprint,
          ),
          AppTextField(
            controller: _reason,
            label: l.adminAiQuotaReason,
            prefixIcon: Icons.notes_outlined,
          ),
          AppSpacing.gapSm,
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _limit.toDouble().clamp(0, _maxLimit.toDouble()),
                  min: 0,
                  max: _maxLimit.toDouble(),
                  divisions: 100,
                  label: '$_limit',
                  onChanged: widget.working
                      ? null
                      : (v) => setState(() => _limit = v.round()),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '$_limit',
                  textAlign: TextAlign.right,
                  style: context.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: PremiumButton(
              label: l.adminAiQuotaAddOverride,
              leadingIcon: Icons.add,
              onPressed: widget.working ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverridesList extends ConsumerWidget {
  const _OverridesList({
    required this.rows,
    required this.working,
    required this.onRemove,
  });
  final List<AiUserOverride> rows;
  final bool working;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (rows.isEmpty) {
      return PremiumCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(l.adminAiQuotaNoOverrides),
      );
    }
    final page = ref.watch(aiOverridesPageProvider);
    return Column(
      children: [
        for (final r in rows) ...[
          PremiumCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.userEmail ?? r.userId,
                        style: context.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${l.adminAiQuotaLimitField}: ${r.dailyCallLimit}'
                        '${r.reason != null ? ' · ${r.reason}' : ''}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l.adminAiQuotaRemoveOverride,
                  onPressed: working ? null : () => onRemove(r.userId),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        AppSpacing.gapSm,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous',
              onPressed: page.offset == 0
                  ? null
                  : () => ref.read(aiOverridesPageProvider.notifier).state =
                      _OverridesPage(
                        (page.offset - page.limit).clamp(0, 1 << 31),
                        page.limit,
                      ),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${page.offset + 1}–${page.offset + rows.length}'),
            IconButton(
              tooltip: 'Next',
              onPressed: rows.length < page.limit
                  ? null
                  : () => ref.read(aiOverridesPageProvider.notifier).state =
                      _OverridesPage(page.offset + page.limit, page.limit),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
