// ============================================================================
// Audit Center · Detail de un report (PR-Audit-3)
// ----------------------------------------------------------------------------
// `/admin/audit/:id` -- detalle de un report concreto.
//
// Estructura:
//   - PageHeader con breadcrumb (Audit Center > Report) + acciones
//     (Refresh, Download TXT).
//   - Meta-info (started_at, duration, findings count).
//   - Si status='running': banner explicativo + polling cada 4s.
//   - Si status='failed': banner de error.
//   - Si status='completed' y no hay findings: empty state limpio.
//   - Sino: findings agrupados por severity con `_FindingsSection`.
//
// Polling: igual que en la lista, mientras el report sea 'running'
// re-pediremos el detail. Cuando pase a 'completed' el timer se cancela.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/audit_center_providers.dart';
import '../../domain/audit_report.dart';
import '../util/audit_txt_download.dart';
import '../util/audit_txt_export.dart';
import '../widgets/audit_severity_chip.dart';

class AdminAuditReportPage extends ConsumerStatefulWidget {
  const AdminAuditReportPage({required this.reportId, super.key});

  final String reportId;

  @override
  ConsumerState<AdminAuditReportPage> createState() =>
      _AdminAuditReportPageState();
}

class _AdminAuditReportPageState
    extends ConsumerState<AdminAuditReportPage> {
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _maybePoll(AuditReport report) {
    final running = report.status == AuditReportStatus.running;
    if (running) {
      if (_pollTimer == null || !_pollTimer!.isActive) {
        _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
          if (!mounted) {
            _pollTimer?.cancel();
            _pollTimer = null;
            return;
          }
          ref.invalidate(auditReportDetailProvider(widget.reportId));
        });
      }
    } else if (_pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
  }

  void _exportTxt(AuditReport report) {
    final l = context.l10n;
    final txt = renderAuditReportAsTxt(report);
    final shortId = report.id.length >= 8 ? report.id.substring(0, 8) : report.id;
    downloadTextFile(
      filename: l.adminAuditTxtFilename(shortId),
      text: txt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(auditReportDetailProvider(widget.reportId));

    async.whenData(_maybePoll);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.adminAudit),
        ),
        title: Text(l.adminAuditTitle),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: AppLoadingState(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppErrorState(
                message: l.adminAuditDetailLoadError,
                detail: e.toString(),
                onRetry: () => ref.invalidate(
                  auditReportDetailProvider(widget.reportId),
                ),
                retryLabel: l.actionRetry,
              ),
            ),
            data: (report) => _Body(
              report: report,
              onRefresh: () => ref.invalidate(
                auditReportDetailProvider(widget.reportId),
              ),
              onExport: () => _exportTxt(report),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.report,
    required this.onRefresh,
    required this.onExport,
  });

  final AuditReport report;
  final VoidCallback onRefresh;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final dateFmt = DateFormat.yMMMd(localeCode).add_Hm();
    final scheme = Theme.of(context).colorScheme;

    final isRunning = report.status == AuditReportStatus.running;
    final isFailed = report.status == AuditReportStatus.failed;
    final canExport = !isRunning;

    final durationLabel = report.duration != null
        ? l.adminAuditDurationSeconds(
            report.duration!.inSeconds.toString(),
          )
        : l.adminAuditDurationRunning;

    final grouped = report.findingsBySeverity();
    final orderedSevs = [
      AuditSeverity.critical,
      AuditSeverity.high,
      AuditSeverity.medium,
      AuditSeverity.low,
      AuditSeverity.info,
    ];

    final hasAnyFinding = report.findings.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: l.adminAuditTitle,
            subtitle: l.adminAuditDetailMeta(
              dateFmt.format(report.startedAt.toLocal()),
              durationLabel,
              report.findings.length,
            ),
            breadcrumb: [
              BreadcrumbItem(
                label: l.adminAuditDetailBackToList,
                onTap: () => context.goNamed(RouteNames.adminAudit),
              ),
              BreadcrumbItem(
                label: report.id.length >= 8
                    ? report.id.substring(0, 8)
                    : report.id,
              ),
            ],
            actions: [
              PremiumButton(
                label: l.adminAuditDetailRefresh,
                variant: PremiumButtonVariant.secondary,
                size: PremiumButtonSize.sm,
                leadingIcon: Icons.refresh_rounded,
                onPressed: onRefresh,
              ),
              PremiumButton(
                label: l.adminAuditDetailExportTxt,
                variant: PremiumButtonVariant.secondary,
                size: PremiumButtonSize.sm,
                leadingIcon: Icons.download_rounded,
                onPressed: canExport ? onExport : null,
              ),
            ],
          ),
          AppSpacing.gapMd,
          if (isRunning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _InfoBanner(
                icon: Icons.hourglass_top_rounded,
                color: scheme.primary,
                text: l.adminAuditDetailRunningHint,
              ),
            ),
          if (isFailed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _InfoBanner(
                icon: Icons.error_outline_rounded,
                color: scheme.error,
                text: report.error != null && report.error!.isNotEmpty
                    ? l.adminAuditDetailFailedError(report.error!)
                    : l.adminAuditDetailFailed,
              ),
            ),
          if (!isRunning && !isFailed && !hasAnyFinding)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _InfoBanner(
                icon: Icons.verified_rounded,
                color: const Color(0xFF10B981),
                text: l.adminAuditDetailEmpty,
              ),
            ),
          if (hasAnyFinding) ...[
            const SizedBox(height: AppSpacing.md),
            for (final sev in orderedSevs)
              if (grouped[sev]!.isNotEmpty) ...[
                _FindingsSection(
                  severity: sev,
                  findings: grouped[sev]!,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FindingsSection extends StatelessWidget {
  const _FindingsSection({
    required this.severity,
    required this.findings,
  });

  final AuditSeverity severity;
  final List<AuditFinding> findings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: 4,
              right: 4,
              bottom: AppSpacing.sm,
            ),
            child: Row(
              children: [
                AuditSeverityChip(
                  severity: severity,
                  count: findings.length,
                ),
              ],
            ),
          ),
          for (final f in findings) ...[
            _FindingCard(finding: f),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _FindingCard extends StatefulWidget {
  const _FindingCard({required this.finding});

  final AuditFinding finding;

  @override
  State<_FindingCard> createState() => _FindingCardState();
}

class _FindingCardState extends State<_FindingCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final f = widget.finding;
    final scheme = Theme.of(context).colorScheme;
    final hasDetails = f.details != null && f.details!.isNotEmpty;

    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  f.title,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _CheckIdChip(checkId: f.checkId),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (f.impact.isNotEmpty) ...[
            _Label(text: l.adminAuditFindingImpact),
            const SizedBox(height: 2),
            Text(
              f.impact,
              style: context.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (f.recommendation.isNotEmpty) ...[
            _Label(text: l.adminAuditFindingRecommendation),
            const SizedBox(height: 2),
            Text(
              f.recommendation,
              style: context.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              if (f.affectedCount > 0) ...[
                Icon(
                  Icons.people_alt_outlined,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  l.adminAuditFindingAffected(f.affectedCount),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              if (hasDetails)
                TextButton.icon(
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  label: Text(l.adminAuditFindingDetails),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
            ],
          ),
          if (hasDetails && _expanded) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: AppRadii.brSm,
              ),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(f.details),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.textTheme.labelSmall?.copyWith(
        color: context.colors.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _CheckIdChip extends StatelessWidget {
  const _CheckIdChip({required this.checkId});
  final String checkId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: AppRadii.brSm,
      ),
      child: Text(
        checkId,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
