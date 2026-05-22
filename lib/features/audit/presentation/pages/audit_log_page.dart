import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_pagination_bar.dart';
import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/features/audit/domain/audit_log_entry.dart';
import 'package:myapp/features/audit/presentation/audit_event_visuals.dart';

/// Página `/audit-log` — lista los últimos eventos del usuario (login,
/// cambios de cuenta, MFA, passkey…). Append-only por RLS: el usuario
/// no puede modificar ni borrar.
class AuditLogPage extends ConsumerWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.accountSettings),
        ),
        title: Text(l.auditLogTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myAuditLogProvider),
          ),
        ],
      ),
      body: const AuditLogView(),
    );
  }
}

/// Cuerpo del audit-log (sin Scaffold). Reutilizable como página completa o
/// embebido en el master-detail de Ajustes → Workspace.
class AuditLogView extends ConsumerStatefulWidget {
  const AuditLogView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll: usa `shrinkWrap`.
  final bool embedded;

  @override
  ConsumerState<AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends ConsumerState<AuditLogView> {
  int _page = 0;
  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final entriesAsync = ref.watch(myAuditLogProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l.authErrorUnknown,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l.auditLogEmpty,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            final totalPages = (entries.length / _pageSize).ceil();
            final page = _page.clamp(0, totalPages - 1);
            final start = page * _pageSize;
            final end = (start + _pageSize) > entries.length
                ? entries.length
                : start + _pageSize;
            final pageEntries = entries.sublist(start, end);
            final list = ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shrinkWrap: widget.embedded,
              physics: widget.embedded
                  ? const NeverScrollableScrollPhysics()
                  : null,
              itemCount: pageEntries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _AuditTile(entry: pageEntries[i]),
            );
            return Column(
              mainAxisSize:
                  widget.embedded ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (widget.embedded) list else Expanded(child: list),
                AppPaginationBar(
                  currentPage: page,
                  totalPages: totalPages,
                  onPrevious: () => setState(() => _page = page - 1),
                  onNext: () => setState(() => _page = page + 1),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final formatter = DateFormat.yMMMd(localeCode).add_Hm();
    return ListTile(
      leading:
          Icon(iconForAuditEvent(entry.event), color: context.colors.primary),
      title: Text(labelForAuditEvent(l, entry.event)),
      subtitle: Text(formatter.format(entry.occurredAt.toLocal())),
      dense: true,
    );
  }
}
