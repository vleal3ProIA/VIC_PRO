// ============================================================================
// /admin/errors/:id -- Detalle de un error report con diagnostico IA
// ----------------------------------------------------------------------------
// El admin ve:
//   - Header: fn + severidad + fechas + user_id corto.
//   - `error_message`.
//   - JSON pretty-printed de `error_details` y `context`.
//   - Boton "Diagnosticar con IA" si `ai_diagnosis` esta vacio. Cuando
//     responde, se revela 3 secciones (why, what_user_did, how_to_fix).
//     Si ya hay diagnostico cacheado, las 3 secciones aparecen directas.
//   - Boton "Marcar resuelto" (con notas opcionales).
//   - Boton "Borrar" (con confirmacion).
//
// Importante: este es el UNICO sitio de la app donde se muestran detalles
// tecnicos sin pasar por `mapBackendError`. Por router_guards + RLS, solo
// admin/super entran aqui.
// ============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/error_reports_providers.dart';
import '../../domain/error_report.dart';

class AdminErrorDetailPage extends ConsumerWidget {
  const AdminErrorDetailPage({required this.errorId, super.key});

  final String errorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(errorReportProvider(errorId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.adminErrors),
        ),
        title: Text(l.adminErrorsDetailTitle),
      ),
      body: async.when(
        loading: () => const Center(child: AppLoadingState()),
        error: (e, _) => AppErrorState(
          message: l.adminErrorsLoadError,
          detail: e.toString(),
          onRetry: () => ref.invalidate(errorReportProvider(errorId)),
          retryLabel: l.actionRetry,
        ),
        data: (report) {
          if (report == null) {
            return Center(child: Text(l.adminErrorsLoadError));
          }
          return _DetailBody(report: report);
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.report});
  final ErrorReport report;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _diagnosing = false;
  String? _diagnoseError;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();
    final report = widget.report;
    final scheme = context.colors;
    final hasAi = report.aiDiagnosis != null && report.aiDiagnosis!.isComplete;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header card ──
              PremiumCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.fn,
                            style: context.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _SeverityChip(severity: report.severity),
                        const SizedBox(width: AppSpacing.xs),
                        _StatusChip(status: report.status),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: 2,
                      children: [
                        _LabelValue(
                          label: l.adminErrorsColumnDate,
                          value: fmt.format(report.createdAt.toLocal()),
                        ),
                        if (report.userId != null)
                          _LabelValue(
                            label: l.adminErrorsColumnUser,
                            value:
                                '${report.userId!.substring(0, 8)}… (${report.userId!.length})',
                          ),
                        if (report.errorCode != null)
                          _LabelValue(
                            label: 'error_code',
                            value: report.errorCode!,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              // ── Mensaje ──
              PremiumCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.adminErrorsDetailMessage,
                      style: context.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SelectableText(
                      report.errorMessage,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              // ── Context ──
              if (report.context != null)
                _JsonBlock(
                  label: l.adminErrorsDetailContext,
                  value: report.context,
                ),
              if (report.context != null) AppSpacing.gapMd,
              // ── Details ──
              _JsonBlock(
                label: l.adminErrorsDetailDetails,
                value: report.errorDetails,
              ),
              AppSpacing.gapMd,
              // ── AI diagnosis ──
              PremiumCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          l.adminErrorsDetailAiDiagnosis,
                          style: context.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (!hasAi)
                          PremiumButton(
                            label: _diagnosing
                                ? l.adminErrorsDetailAiDiagnosing
                                : l.adminErrorsDetailAiDiagnose,
                            onPressed: _diagnosing ? null : _onDiagnose,
                            loading: _diagnosing,
                            leadingIcon: Icons.auto_awesome,
                          ),
                      ],
                    ),
                    if (_diagnosing) ...[
                      const SizedBox(height: AppSpacing.md),
                      const LinearProgressIndicator(),
                    ],
                    if (_diagnoseError != null && !_diagnosing) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _diagnoseError!,
                        style: TextStyle(color: scheme.error),
                      ),
                    ],
                    if (hasAi) ...[
                      const SizedBox(height: AppSpacing.md),
                      _AiSection(
                        title: l.adminErrorsDetailAiWhy,
                        body: report.aiDiagnosis!.why,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _AiSection(
                        title: l.adminErrorsDetailAiWhatUserDid,
                        body: report.aiDiagnosis!.whatUserDid,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _AiSection(
                        title: l.adminErrorsDetailAiHowToFix,
                        body: report.aiDiagnosis!.howToFix,
                      ),
                    ],
                  ],
                ),
              ),
              AppSpacing.gapLg,
              // ── Acciones ──
              Row(
                children: [
                  PremiumButton(
                    label: l.adminErrorsDetailResolve,
                    onPressed: report.status == ErrorReportStatus.resolved
                        ? null
                        : _onResolve,
                    leadingIcon: Icons.check_circle_outline,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: _onDelete,
                    icon: Icon(Icons.delete_outline, color: scheme.error),
                    label: Text(
                      l.adminErrorsDetailDelete,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onDiagnose() async {
    if (_diagnosing) return;
    setState(() {
      _diagnosing = true;
      _diagnoseError = null;
    });
    final l = context.l10n;
    final ds = ref.read(errorReportsDataSourceProvider);
    try {
      await ds.diagnose(widget.report.id);
      // Re-fetch para que la UI muestre la cache nueva.
      ref.invalidate(errorReportProvider(widget.report.id));
    } catch (_) {
      if (mounted) {
        setState(() => _diagnoseError = l.adminErrorsDetailDiagnoseFailed);
      }
    } finally {
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  Future<void> _onResolve() async {
    final l = context.l10n;
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.adminErrorsDetailResolveTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.adminErrorsDetailResolveBody),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: notesCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l.adminErrorsDetailResolveNotes,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l.adminErrorsDetailResolveConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final resolvedMsg = l.adminErrorsDetailResolved;
    try {
      await ref.read(errorReportsDataSourceProvider).updateStatus(
            id: widget.report.id,
            status: ErrorReportStatus.resolved,
            notes: notesCtrl.text,
          );
      ref
        ..invalidate(errorReportProvider(widget.report.id))
        ..invalidate(errorReportsListProvider);
      messenger.showSnackBar(SnackBar(content: Text(resolvedMsg)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _onDelete() async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.adminErrorsDetailDeleteTitle,
      body: l.adminErrorsDetailDeleteBody,
      confirmLabel: l.adminErrorsDetailDelete,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final deletedMsg = l.adminErrorsDetailDeleted;
    try {
      await ref
          .read(errorReportsDataSourceProvider)
          .delete(widget.report.id);
      ref.invalidate(errorReportsListProvider);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(deletedMsg)));
        // Navegamos atras (no podemos quedarnos en el detail de un id borrado).
        context.popOrGo(RouteNames.adminErrors);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _AiSection extends StatelessWidget {
  const _AiSection({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          body,
          style: context.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
      ],
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.label, required this.value});
  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    const encoder = JsonEncoder.withIndent('  ');
    String pretty;
    try {
      pretty = encoder.convert(value);
    } catch (_) {
      pretty = value?.toString() ?? 'null';
    }
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: AppRadii.brSm,
            ),
            child: SelectableText(
              pretty,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return RichText(
      text: TextSpan(
        style: context.textTheme.bodySmall,
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({required this.severity});
  final ErrorReportSeverity severity;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    switch (severity) {
      case ErrorReportSeverity.low:
        return PremiumBadge(
          label: l.adminErrorsSeverityLow,
          variant: PremiumBadgeVariant.neutral,
        );
      case ErrorReportSeverity.medium:
        return PremiumBadge(
          label: l.adminErrorsSeverityMedium,
          variant: PremiumBadgeVariant.warning,
        );
      case ErrorReportSeverity.high:
        return PremiumBadge(
          label: l.adminErrorsSeverityHigh,
          variant: PremiumBadgeVariant.error,
        );
      case ErrorReportSeverity.critical:
        return PremiumBadge(
          label: l.adminErrorsSeverityCritical,
          variant: PremiumBadgeVariant.error,
        );
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ErrorReportStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    switch (status) {
      case ErrorReportStatus.open:
        return PremiumBadge(
          label: l.adminErrorsStatusOpen,
          variant: PremiumBadgeVariant.info,
        );
      case ErrorReportStatus.inProgress:
        return PremiumBadge(
          label: l.adminErrorsStatusInProgress,
          variant: PremiumBadgeVariant.warning,
        );
      case ErrorReportStatus.resolved:
        return PremiumBadge(
          label: l.adminErrorsStatusResolved,
          variant: PremiumBadgeVariant.success,
        );
      case ErrorReportStatus.dismissed:
        return PremiumBadge(
          label: l.adminErrorsStatusDismissed,
          variant: PremiumBadgeVariant.neutral,
        );
    }
  }
}
