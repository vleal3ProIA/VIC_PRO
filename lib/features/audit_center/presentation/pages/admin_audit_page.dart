// ============================================================================
// Audit Center · Lista de reports (PR-Audit-3)
// ----------------------------------------------------------------------------
// `/admin/audit` -- entry point del modulo. Muestra:
//   - PageHeader con titulo + subtitle + accion "Run new audit"
//   - Lista de reports recientes (max 20) con summary, fecha, duracion,
//     status badge.
//
// Si hay un report con status='running' (porque acabas de pulsar el
// boton o porque hay otro admin lanzandolo), arrancamos polling cada
// 4s hasta que todos hayan terminado.
//
// El boton "Run new audit" muestra spinner mientras invoca la Edge
// Function, y al exito navega directamente al detail del nuevo report.
// Rate limit = 1/min/admin lo aplica el backend -- aqui solo mostramos
// snackbar localizado si llega 429.
// ============================================================================

import 'dart:async';

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
import 'package:myapp/core/widgets/app_pagination_bar.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/audit_center_providers.dart';
import '../../data/audit_center_datasource.dart';
import '../../domain/audit_report.dart';
import '../../domain/audit_staleness.dart';
import '../widgets/audit_severity_chip.dart';

class AdminAuditPage extends ConsumerWidget {
  const AdminAuditPage({super.key});

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
        title: Text(l.adminAuditTitle),
      ),
      body: const AdminAuditView(),
    );
  }
}

/// Cuerpo del Audit Center (sin Scaffold). Reutilizable como página completa
/// o embebido en el master-detail de Administración.
class AdminAuditView extends ConsumerStatefulWidget {
  const AdminAuditView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Admin).
  final bool embedded;

  @override
  ConsumerState<AdminAuditView> createState() => _AdminAuditViewState();
}

class _AdminAuditViewState extends ConsumerState<AdminAuditView> {
  /// Polling activo mientras haya algun report con status='running'.
  /// Mismo patron que `files_page.dart` para virus_scan_status=pending.
  Timer? _pollTimer;

  /// Spinner del boton mientras esta corriendo la Edge Function.
  bool _starting = false;

  /// Página actual (0-indexed) de la paginación client-side.
  int _page = 0;

  /// Reports por página.
  static const int _pageSize = 10;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Si hay un report 'running' arranca / mantiene polling, sino lo
  /// cancela. Llamado cada vez que la lista cambia.
  void _maybePollRunning(List<AuditReportSummaryRow> rows) {
    final hasRunning = rows.any((r) => r.status == AuditReportStatus.running);
    if (hasRunning) {
      if (_pollTimer == null || !_pollTimer!.isActive) {
        _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
          if (!mounted) {
            _pollTimer?.cancel();
            _pollTimer = null;
            return;
          }
          ref.invalidate(auditReportsListProvider);
        });
      }
    } else if (_pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _runAudit() async {
    if (_starting) return;
    setState(() => _starting = true);
    // Capturamos todo lo derivado de context ANTES del await para no
    // disparar `use_build_context_synchronously` despues del gap.
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errorBg = Theme.of(context).colorScheme.error;
    final startedMsg = l.adminAuditRunStarted;
    final genericErr = l.adminAuditRunErrorGeneric;
    final rateErr = l.adminAuditRunErrorRate;
    final forbiddenErr = l.adminAuditRunErrorForbidden;
    final authErr = l.adminAuditRunErrorAuth;
    try {
      final id = await ref.read(auditCenterDataSourceProvider).startAudit();
      // Refrescamos lista para que la nueva row 'running' aparezca, y
      // navegamos al detail (que arranca su propio polling).
      ref.invalidate(auditReportsListProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(startedMsg),
          duration: AppDurations.snack,
        ),
      );
      if (mounted) {
        await context.pushNamed(
          RouteNames.adminAuditDetail,
          pathParameters: {'id': id},
        );
      }
    } on AuditRunException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _mapErrorCode(
              code: e.code,
              rate: rateErr,
              forbidden: forbiddenErr,
              auth: authErr,
              generic: genericErr,
            ),
          ),
          duration: AppDurations.snackLong,
          backgroundColor: errorBg,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(genericErr),
          duration: AppDurations.snackLong,
          backgroundColor: errorBg,
        ),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Mapea el `error.code` que devuelve `run-audit` a uno de los
  /// strings localizados que ya capturamos pre-await. Funcion pura --
  /// no toca `BuildContext`.
  String _mapErrorCode({
    required String code,
    required String rate,
    required String forbidden,
    required String auth,
    required String generic,
  }) {
    switch (code) {
      case 'rate_limited':
        return rate;
      case 'forbidden':
        return forbidden;
      case 'invalid_token':
      case 'missing_authorization':
        return auth;
      default:
        return generic;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(auditReportsListProvider);

    // Mantenemos polling sincronizado con el ultimo `data` que vimos.
    async.whenData(_maybePollRunning);

    // Botón "Run audit" (estaba en el PageHeader de la página completa).
    final runButton = PremiumButton(
      label: _starting ? l.adminAuditRunning : l.adminAuditRunButton,
      onPressed: _starting ? null : _runAudit,
      loading: _starting,
      leadingIcon: Icons.shield_outlined,
    );

    final content = async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: AppLoadingState(),
      ),
      error: (e, _) => AppErrorState(
        message: l.adminAuditListLoadError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(auditReportsListProvider),
        retryLabel: l.actionRetry,
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: AppEmptyState(
              icon: Icons.shield_outlined,
              title: l.adminAuditEmptyTitle,
              message: l.adminAuditEmptyBody,
            ),
          );
        }
        // El banner de staleness y el polling evalúan sobre la lista
        // completa; solo paginamos la visualización.
        final staleness = evaluateAuditStaleness(rows);
        final totalPages = (rows.length / _pageSize).ceil();
        final page = _page.clamp(0, totalPages - 1);
        final start = page * _pageSize;
        final end =
            (start + _pageSize) > rows.length ? rows.length : start + _pageSize;
        final pageRows = rows.sublist(start, end);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (staleness.isStale) ...[
              _StaleBanner(staleness: staleness),
              const SizedBox(height: AppSpacing.md),
            ],
            for (final r in pageRows) ...[
              _AuditReportRow(row: r),
              const SizedBox(height: AppSpacing.sm),
            ],
            AppPaginationBar(
              currentPage: page,
              totalPages: totalPages,
              onPrevious: () => setState(() => _page = page - 1),
              onNext: () => setState(() => _page = page + 1),
            ),
          ],
        );
      },
    );

    // Embebido: cabecera de acción (run + refresh) + contenido, sin scroll
    // propio (lo provee el master-detail de Admin).
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: l.actionRetry,
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(auditReportsListProvider),
                ),
                const SizedBox(width: AppSpacing.sm),
                runButton,
              ],
            ),
          ),
          AppSpacing.gapMd,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: content,
          ),
        ],
      );
    }

    // Página completa.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: l.adminAuditTitle,
                subtitle: l.adminAuditSubtitle,
                actions: [runButton],
              ),
              AppSpacing.gapMd,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
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

/// Una fila de la lista de reports. Card clickable que lleva al detail.
class _AuditReportRow extends StatelessWidget {
  const _AuditReportRow({required this.row});

  final AuditReportSummaryRow row;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final dateFmt = DateFormat.yMMMd(localeCode).add_Hm();
    final scheme = Theme.of(context).colorScheme;

    final isRunning = row.status == AuditReportStatus.running;
    final isFailed = row.status == AuditReportStatus.failed;
    final severeCount = row.summary.count(AuditSeverity.critical) +
        row.summary.count(AuditSeverity.high);
    final headline = severeCount == 0
        ? l.adminAuditNoSevereFindings
        : l.adminAuditSevereFindingsCount(severeCount);

    return PremiumCard(
      onTap: () => context.pushNamed(
        RouteNames.adminAuditDetail,
        pathParameters: {'id': row.id},
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _statusIcon(row.status),
                size: 18,
                color: _statusColor(scheme, row.status, severeCount),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isFailed
                      ? l.adminAuditReportStatusFailed
                      : isRunning
                          ? l.adminAuditReportStatusRunning
                          : headline,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              _StatusBadge(status: row.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Pills de severity counts.
          if (!isRunning && !isFailed)
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final sev in AuditSeverity.values)
                  if (row.summary.count(sev) > 0)
                    AuditSeverityChip(
                      severity: sev,
                      count: row.summary.count(sev),
                      dense: true,
                    ),
              ],
            ),
          if (!isRunning && !isFailed) const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                dateFmt.format(row.startedAt.toLocal()),
                style: context.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (row.duration != null) ...[
                Icon(
                  Icons.schedule_outlined,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  l.adminAuditReportRowDuration(
                    row.duration!.inSeconds.toString(),
                  ),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(AuditReportStatus s) {
    switch (s) {
      case AuditReportStatus.running:
        return Icons.hourglass_top_rounded;
      case AuditReportStatus.completed:
        return Icons.task_alt_rounded;
      case AuditReportStatus.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color _statusColor(
    ColorScheme scheme,
    AuditReportStatus s,
    int severeCount,
  ) {
    switch (s) {
      case AuditReportStatus.running:
        return scheme.primary;
      case AuditReportStatus.completed:
        return severeCount == 0
            ? const Color(0xFF10B981) // emerald = limpio
            : scheme.error;
      case AuditReportStatus.failed:
        return scheme.error;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final AuditReportStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    switch (status) {
      case AuditReportStatus.running:
        return PremiumBadge(
          label: l.adminAuditReportStatusRunning,
          variant: PremiumBadgeVariant.info,
          icon: Icons.circle_rounded,
          dense: true,
        );
      case AuditReportStatus.completed:
        return PremiumBadge(
          label: l.adminAuditReportStatusCompleted,
          variant: PremiumBadgeVariant.success,
          dense: true,
        );
      case AuditReportStatus.failed:
        return PremiumBadge(
          label: l.adminAuditReportStatusFailed,
          variant: PremiumBadgeVariant.error,
          dense: true,
        );
    }
  }
}

/// Banner discreto sugiriendo lanzar un audit nuevo. Aparece cuando el
/// ultimo report es failed o esta a >= 7 dias (logica en
/// `evaluateAuditStaleness`). NO bloquea -- es solo un hint visual.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.staleness});

  final AuditStaleness staleness;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final isFailed = staleness.reason == 'last_failed';

    final title = isFailed
        ? l.adminAuditStaleFailedTitle
        : l.adminAuditStaleTitle(staleness.daysSinceLast ?? 0);
    final body = isFailed ? l.adminAuditStaleFailedBody : l.adminAuditStaleBody;
    final color = isFailed
        ? scheme.error
        : const Color(0xFFF59E0B); // amber-500 -- warning suave

    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isFailed ? Icons.error_outline_rounded : Icons.schedule_outlined,
            color: color,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
