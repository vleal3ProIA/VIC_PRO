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
class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  int _page = 0;
  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final entriesAsync = ref.watch(myAuditLogProvider);

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
      body: Center(
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
              return Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      itemCount: pageEntries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _AuditTile(entry: pageEntries[i]),
                    ),
                  ),
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
      leading: Icon(iconForAuditEvent(entry.event), color: context.colors.primary),
      title: Text(labelForAuditEvent(l, entry.event)),
      subtitle: Text(formatter.format(entry.occurredAt.toLocal())),
      dense: true,
    );
  }
}
