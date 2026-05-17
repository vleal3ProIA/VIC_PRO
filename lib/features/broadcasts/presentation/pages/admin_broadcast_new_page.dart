import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/features/billing/application/admin_plans_providers.dart';

import '../../application/broadcasts_providers.dart';
import '../../domain/broadcast.dart';

/// `/admin/broadcasts/new` — formulario para crear y disparar un
/// broadcast. 3 secciones: contenido, audiencia, acciones.
class AdminBroadcastNewPage extends ConsumerStatefulWidget {
  const AdminBroadcastNewPage({super.key});

  @override
  ConsumerState<AdminBroadcastNewPage> createState() =>
      _AdminBroadcastNewPageState();
}

class _AdminBroadcastNewPageState
    extends ConsumerState<AdminBroadcastNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  BroadcastTargetType _targetType = BroadcastTargetType.all;
  String _planSlug = '';
  String _languageCode = 'en';
  String _userStatus = 'active';

  // Estimate (cuántos users recibirán) — se recalcula al cambiar target.
  BroadcastEstimate? _estimate;
  bool _estimating = false;
  bool _sendingTest = false;
  bool _sending = false;
  Timer? _estimateDebounce;

  @override
  void initState() {
    super.initState();
    // Disparar primera estimación con target=all.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleEstimate());
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    _estimateDebounce?.cancel();
    super.dispose();
  }

  void _scheduleEstimate() {
    _estimateDebounce?.cancel();
    _estimateDebounce =
        Timer(const Duration(milliseconds: 200), _runEstimate);
  }

  Future<void> _runEstimate() async {
    setState(() => _estimating = true);
    try {
      final est =
          await ref.read(broadcastsDataSourceProvider).estimate(
                targetType: _targetType,
                targetValue: _currentTargetValue(),
              );
      if (!mounted) return;
      setState(() {
        _estimate = est;
        _estimating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estimate = null;
        _estimating = false;
      });
    }
  }

  Map<String, dynamic> _currentTargetValue() {
    switch (_targetType) {
      case BroadcastTargetType.all:
        return const {};
      case BroadcastTargetType.plan:
        return {'slug': _planSlug};
      case BroadcastTargetType.language:
        return {'code': _languageCode};
      case BroadcastTargetType.status:
        return {'status': _userStatus};
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plansAsync = ref.watch(allPlansAdminProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.adminBroadcasts),
        ),
        title: Text(l.broadcastsNew),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(l.broadcastsSectionContent),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _subjectCtrl,
                            enabled: !_sending,
                            maxLength: 200,
                            decoration: InputDecoration(
                              labelText: l.broadcastsFieldSubject,
                              prefixIcon: const Icon(Icons.subject),
                            ),
                            validator: (v) {
                              final s = v?.trim() ?? '';
                              if (s.isEmpty) return l.broadcastsSubjectRequired;
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _bodyCtrl,
                            enabled: !_sending,
                            maxLength: 5000,
                            minLines: 6,
                            maxLines: 14,
                            decoration: InputDecoration(
                              labelText: l.broadcastsFieldBody,
                              helperText: l.broadcastsFieldBodyHint,
                              alignLabelWithHint: true,
                            ),
                            validator: (v) {
                              final s = v?.trim() ?? '';
                              if (s.isEmpty) return l.broadcastsBodyRequired;
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(l.broadcastsSectionAudience),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<BroadcastTargetType>(
                            initialValue: _targetType,
                            decoration: InputDecoration(
                              labelText: l.broadcastsFieldTarget,
                              prefixIcon: const Icon(Icons.groups_outlined),
                            ),
                            onChanged: _sending
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() => _targetType = v);
                                      _scheduleEstimate();
                                    }
                                  },
                            items: [
                              DropdownMenuItem(
                                value: BroadcastTargetType.all,
                                child: Text(l.broadcastsTargetOptionAll),
                              ),
                              DropdownMenuItem(
                                value: BroadcastTargetType.plan,
                                child: Text(l.broadcastsTargetOptionPlan),
                              ),
                              DropdownMenuItem(
                                value: BroadcastTargetType.language,
                                child:
                                    Text(l.broadcastsTargetOptionLanguage),
                              ),
                              DropdownMenuItem(
                                value: BroadcastTargetType.status,
                                child: Text(l.broadcastsTargetOptionStatus),
                              ),
                            ],
                          ),
                          if (_targetType == BroadcastTargetType.plan) ...[
                            const SizedBox(height: 8),
                            plansAsync.when(
                              loading: () =>
                                  const LinearProgressIndicator(),
                              error: (_, __) =>
                                  Text(l.broadcastsLoadPlansError),
                              data: (plans) {
                                if (_planSlug.isEmpty && plans.isNotEmpty) {
                                  _planSlug = plans.first.slug;
                                  WidgetsBinding.instance
                                      .addPostFrameCallback(
                                    (_) => _scheduleEstimate(),
                                  );
                                }
                                return DropdownButtonFormField<String>(
                                  initialValue: _planSlug.isEmpty
                                      ? null
                                      : _planSlug,
                                  decoration: InputDecoration(
                                    labelText: l.broadcastsFieldPlan,
                                    prefixIcon: const Icon(
                                      Icons.workspace_premium_outlined,
                                    ),
                                  ),
                                  onChanged: _sending
                                      ? null
                                      : (v) {
                                          if (v != null) {
                                            setState(() => _planSlug = v);
                                            _scheduleEstimate();
                                          }
                                        },
                                  items: [
                                    for (final p in plans)
                                      DropdownMenuItem(
                                        value: p.slug,
                                        child: Text(p.name),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                          if (_targetType ==
                              BroadcastTargetType.language) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _languageCode,
                              decoration: InputDecoration(
                                labelText: l.broadcastsFieldLanguage,
                                prefixIcon:
                                    const Icon(Icons.language_outlined),
                              ),
                              onChanged: _sending
                                  ? null
                                  : (v) {
                                      if (v != null) {
                                        setState(() => _languageCode = v);
                                        _scheduleEstimate();
                                      }
                                    },
                              items: [
                                for (final loc in AppLocales.all)
                                  DropdownMenuItem(
                                    value: loc.languageCode,
                                    child: Text(
                                      '${AppLocales.flag[loc.languageCode] ?? ''}  '
                                      '${AppLocales.nativeName[loc.languageCode] ?? loc.languageCode}',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (_targetType == BroadcastTargetType.status) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _userStatus,
                              decoration: InputDecoration(
                                labelText: l.broadcastsFieldStatus,
                                prefixIcon:
                                    const Icon(Icons.toggle_on_outlined),
                              ),
                              onChanged: _sending
                                  ? null
                                  : (v) {
                                      if (v != null) {
                                        setState(() => _userStatus = v);
                                        _scheduleEstimate();
                                      }
                                    },
                              items: [
                                DropdownMenuItem(
                                  value: 'active',
                                  child:
                                      Text(l.broadcastsStatusActiveUsers),
                                ),
                                DropdownMenuItem(
                                  value: 'blocked',
                                  child: Text(l.broadcastsStatusBlockedUsers),
                                ),
                                DropdownMenuItem(
                                  value: 'deactivated',
                                  child: Text(
                                    l.broadcastsStatusDeactivatedUsers,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          _EstimatePreview(
                            estimate: _estimate,
                            loading: _estimating,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(l.broadcastsSectionActions),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _sending || _sendingTest
                                ? null
                                : _onSendTest,
                            icon: _sendingTest
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_outlined),
                            label: Text(l.broadcastsSendTest),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _canSend() ? _onSend : null,
                            icon: _sending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.campaign),
                            label: Text(
                              l.broadcastsSendToAudience(
                                _estimate?.count ?? 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _canSend() {
    if (_sending) return false;
    if (_estimate == null) return false;
    if (_estimate!.count == 0) return false;
    return true;
  }

  Future<void> _onSendTest() async {
    final l = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final myEmail = ref.read(currentUserProvider)?.email;
    if (myEmail == null) {
      context.showSnack(l.broadcastsTestNoEmail, isError: true);
      return;
    }
    setState(() => _sendingTest = true);
    try {
      final result = await ref.read(broadcastsDataSourceProvider).sendTest(
            subject: _subjectCtrl.text.trim(),
            bodyHtml: _bodyCtrl.text.trim(),
            toEmail: myEmail,
            locale: ref.read(effectiveLocaleProvider).languageCode,
          );
      if (!mounted) return;
      if (result.ok) {
        context.showSnack(l.broadcastsTestSent(myEmail));
      } else {
        context.showSnack(
          l.broadcastsTestFailed(result.error ?? '?'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sendingTest = false);
    }
  }

  Future<void> _onSend() async {
    final l = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Confirmación con cuenta de destinatarios.
    final confirm = await AppConfirmDialog.show(
      context,
      title: l.broadcastsSendConfirmTitle,
      body: l.broadcastsSendConfirmBody(_estimate?.count ?? 0),
      confirmLabel: l.broadcastsSendNow,
      cancelLabel: l.actionCancel,
    );
    if (confirm != true) return;

    setState(() => _sending = true);
    try {
      final result = await ref.read(broadcastsDataSourceProvider).start(
            subject: _subjectCtrl.text.trim(),
            bodyHtml: _bodyCtrl.text.trim(),
            targetType: _targetType,
            targetValue: _currentTargetValue(),
          );
      if (!mounted) return;
      if (result.ok && result.broadcastId != null) {
        ref.invalidate(broadcastsListProvider);
        context.goNamed(
          RouteNames.adminBroadcastDetail,
          pathParameters: {'id': result.broadcastId!},
        );
      } else {
        setState(() => _sending = false);
        context.showSnack(
          l.broadcastsSendError(result.error ?? '?'),
          isError: true,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      context.showSnack(l.broadcastsSendError('exception'), isError: true);
    }
  }
}

class _EstimatePreview extends StatelessWidget {
  const _EstimatePreview({required this.estimate, required this.loading});
  final BroadcastEstimate? estimate;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (loading) {
      return const LinearProgressIndicator();
    }
    if (estimate == null) {
      return Text(
        l.broadcastsEstimateUnavailable,
        style: TextStyle(color: context.colors.onSurfaceVariant),
      );
    }
    final e = estimate!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.broadcastsEstimateCount(e.count),
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (e.byLocale.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in e.byLocale.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${entry.key.toUpperCase()}  ${entry.value}',
                      style: context.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: context.textTheme.labelMedium?.copyWith(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
