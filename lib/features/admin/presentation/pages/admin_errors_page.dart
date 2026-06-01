// ============================================================================
// /admin/errors -- Lista de error reports
// ----------------------------------------------------------------------------
// Muestra la tabla de `public.error_reports` con filtros de estado y severidad.
// El admin ve fecha, usuario (id corto), funcion, severidad, estado y mensaje
// corto. Click -> detalle (/admin/errors/:id).
//
// Por defecto el filtro arranca con status='open' (lo accionable). El admin
// puede pasar a 'all' o cualquier otro estado.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/error_reports_providers.dart';
import '../../domain/error_report.dart';

class AdminErrorsPage extends ConsumerWidget {
  const AdminErrorsPage({super.key});

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
        title: Text(l.adminErrorsTitle),
      ),
      body: const _AdminErrorsView(),
    );
  }
}

class _AdminErrorsView extends ConsumerWidget {
  const _AdminErrorsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(errorReportsListProvider);
    final filter = ref.watch(errorReportsFilterProvider);

    final content = async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: AppLoadingState(),
      ),
      error: (e, _) => AppErrorState(
        message: l.adminErrorsLoadError,
        // Para el panel admin SI mostramos detalle tecnico: aqui es
        // legitimo (es justamente el sitio para verlo).
        detail: e.toString(),
        onRetry: () => ref.invalidate(errorReportsListProvider),
        retryLabel: l.actionRetry,
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: AppEmptyState(
              icon: Icons.bug_report_outlined,
              title: l.adminErrorsEmptyTitle,
              message: l.adminErrorsEmptyBody,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in rows) ...[
              _ErrorRow(report: r),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.wide),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: l.adminErrorsTitle,
                subtitle: l.adminErrorsSubtitle,
                actions: [
                  IconButton(
                    tooltip: l.actionRetry,
                    icon: const Icon(Icons.refresh),
                    onPressed: () =>
                        ref.invalidate(errorReportsListProvider),
                  ),
                ],
              ),
              AppSpacing.gapMd,
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _Filters(filter: filter),
              ),
              AppSpacing.gapMd,
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: content,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.filter});
  final ErrorReportsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${l.adminErrorsFilterStatus}:',
              style: context.textTheme.bodySmall,
            ),
            const SizedBox(width: AppSpacing.xs),
            DropdownButton<ErrorReportStatus?>(
              value: filter.status,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem<ErrorReportStatus?>(
                  value: null,
                  child: Text(l.adminErrorsFilterAll),
                ),
                DropdownMenuItem(
                  value: ErrorReportStatus.open,
                  child: Text(l.adminErrorsStatusOpen),
                ),
                DropdownMenuItem(
                  value: ErrorReportStatus.inProgress,
                  child: Text(l.adminErrorsStatusInProgress),
                ),
                DropdownMenuItem(
                  value: ErrorReportStatus.resolved,
                  child: Text(l.adminErrorsStatusResolved),
                ),
                DropdownMenuItem(
                  value: ErrorReportStatus.dismissed,
                  child: Text(l.adminErrorsStatusDismissed),
                ),
              ],
              onChanged: (v) {
                ref.read(errorReportsFilterProvider.notifier).state =
                    ErrorReportsFilter(status: v, severity: filter.severity);
              },
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${l.adminErrorsFilterSeverity}:',
              style: context.textTheme.bodySmall,
            ),
            const SizedBox(width: AppSpacing.xs),
            DropdownButton<ErrorReportSeverity?>(
              value: filter.severity,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem<ErrorReportSeverity?>(
                  value: null,
                  child: Text(l.adminErrorsFilterAll),
                ),
                DropdownMenuItem(
                  value: ErrorReportSeverity.low,
                  child: Text(l.adminErrorsSeverityLow),
                ),
                DropdownMenuItem(
                  value: ErrorReportSeverity.medium,
                  child: Text(l.adminErrorsSeverityMedium),
                ),
                DropdownMenuItem(
                  value: ErrorReportSeverity.high,
                  child: Text(l.adminErrorsSeverityHigh),
                ),
                DropdownMenuItem(
                  value: ErrorReportSeverity.critical,
                  child: Text(l.adminErrorsSeverityCritical),
                ),
              ],
              onChanged: (v) {
                ref.read(errorReportsFilterProvider.notifier).state =
                    ErrorReportsFilter(status: filter.status, severity: v);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.report});
  final ErrorReport report;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();
    final scheme = context.colors;

    return PremiumCard(
      onTap: () => context.pushNamed(
        RouteNames.adminErrorDetail,
        pathParameters: {'id': report.id},
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.bug_report_outlined,
            color: _severityColor(scheme, report.severity),
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        report.fn,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _SeverityBadge(severity: report.severity),
                    const SizedBox(width: AppSpacing.xs),
                    _StatusBadge(status: report.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  report.errorMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 2,
                  children: [
                    Text(
                      fmt.format(report.createdAt.toLocal()),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (report.userId != null)
                      Text(
                        '${l.adminErrorsColumnUser}: ${report.userId!.substring(0, 8)}…',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (report.errorCode != null)
                      Text(
                        report.errorCode!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_rounded,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Color _severityColor(ColorScheme scheme, ErrorReportSeverity s) {
    switch (s) {
      case ErrorReportSeverity.low:
        return scheme.onSurfaceVariant;
      case ErrorReportSeverity.medium:
        return const Color(0xFFF59E0B); // amber-500
      case ErrorReportSeverity.high:
        return const Color(0xFFEF4444); // red-500
      case ErrorReportSeverity.critical:
        return scheme.error;
    }
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});
  final ErrorReportSeverity severity;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    switch (severity) {
      case ErrorReportSeverity.low:
        return PremiumBadge(
          label: l.adminErrorsSeverityLow,
          variant: PremiumBadgeVariant.neutral,
          dense: true,
        );
      case ErrorReportSeverity.medium:
        return PremiumBadge(
          label: l.adminErrorsSeverityMedium,
          variant: PremiumBadgeVariant.warning,
          dense: true,
        );
      case ErrorReportSeverity.high:
        return PremiumBadge(
          label: l.adminErrorsSeverityHigh,
          variant: PremiumBadgeVariant.error,
          dense: true,
        );
      case ErrorReportSeverity.critical:
        return PremiumBadge(
          label: l.adminErrorsSeverityCritical,
          variant: PremiumBadgeVariant.error,
          dense: true,
        );
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final ErrorReportStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    switch (status) {
      case ErrorReportStatus.open:
        return PremiumBadge(
          label: l.adminErrorsStatusOpen,
          variant: PremiumBadgeVariant.info,
          dense: true,
        );
      case ErrorReportStatus.inProgress:
        return PremiumBadge(
          label: l.adminErrorsStatusInProgress,
          variant: PremiumBadgeVariant.warning,
          dense: true,
        );
      case ErrorReportStatus.resolved:
        return PremiumBadge(
          label: l.adminErrorsStatusResolved,
          variant: PremiumBadgeVariant.success,
          dense: true,
        );
      case ErrorReportStatus.dismissed:
        return PremiumBadge(
          label: l.adminErrorsStatusDismissed,
          variant: PremiumBadgeVariant.neutral,
          dense: true,
        );
    }
  }
}
