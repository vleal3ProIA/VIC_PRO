import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/locale_provider.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium_badge.dart';

import '../../application/email_log_providers.dart';
import '../../domain/email_log_entry.dart';

/// `/admin/email-log` — auditoría de envíos. Admin-only via RLS.
/// Sirve para debug ("¿le llegó el email a user@x.com?"), compliance
/// (registro GDPR) y soporte. Incluye un botón "Enviar test" para
/// validar la configuración SMTP sin esperar a un evento real.
class AdminEmailLogPage extends ConsumerWidget {
  const AdminEmailLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(emailLogProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.admin),
        ),
        title: Text(l.adminEmailLogTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(emailLogProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.send_outlined),
        label: Text(l.adminEmailLogSendTest),
        onPressed: () => _onSendTest(context, ref),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppMaxWidths.content),
          child: async.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.adminEmailLogLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(emailLogProvider),
              retryLabel: l.actionRetry,
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return AppEmptyState(
                  icon: Icons.mark_email_read_outlined,
                  title: l.adminEmailLogEmptyTitle,
                  message: l.adminEmailLogEmptyBody,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  96,
                ),
                itemCount: entries.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (_, i) => _EntryTile(entry: entries[i]),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onSendTest(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final email = ref.read(currentUserProvider)?.email;
    if (email == null) {
      context.showSnack(l.adminEmailLogTestNoEmail, isError: true);
      return;
    }
    final locale = ref.read(effectiveLocaleProvider).languageCode;
    final result = await ref
        .read(emailLogDataSourceProvider)
        .sendTest(to: email, locale: locale);
    if (!context.mounted) return;
    ref.invalidate(emailLogProvider);
    if (result.ok) {
      context.showSnack(l.adminEmailLogTestSent(email));
    } else {
      context.showSnack(
        l.adminEmailLogTestFailed(result.error ?? '?'),
        isError: true,
      );
    }
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final EmailLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hms();

    final (icon, color) = _statusVisual(context, entry.status);
    final statusLabel = switch (entry.status) {
      EmailLogStatus.sent => l.adminEmailLogStatusSent,
      EmailLogStatus.failed => l.adminEmailLogStatusFailed,
      EmailLogStatus.queued => l.adminEmailLogStatusQueued,
    };
    final statusVariant = switch (entry.status) {
      EmailLogStatus.sent => PremiumBadgeVariant.success,
      EmailLogStatus.failed => PremiumBadgeVariant.error,
      EmailLogStatus.queued => PremiumBadgeVariant.neutral,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(
          entry.subject,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.titleSmall,
        ),
        subtitle: Text(
          '${entry.type} · ${entry.toEmail} · ${entry.locale} · '
          '${fmt.format(entry.createdAt.toLocal())}',
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        trailing: PremiumBadge(
          label: statusLabel,
          variant: statusVariant,
          dense: true,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(context, l.adminEmailLogProvider, entry.provider),
                if (entry.sentAt != null)
                  _kv(
                    context,
                    l.adminEmailLogSentAt,
                    fmt.format(entry.sentAt!.toLocal()),
                  ),
                if (entry.error != null)
                  _kv(
                    context,
                    l.adminEmailLogError,
                    entry.error!,
                    color: context.colors.error,
                  ),
                if (entry.meta.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    l.adminEmailLogMeta,
                    style: context.textTheme.labelSmall,
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      entry.meta.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(
    BuildContext context,
    String k,
    String v, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: context.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _statusVisual(BuildContext context, EmailLogStatus s) {
    switch (s) {
      case EmailLogStatus.sent:
        return (Icons.check_circle, context.colors.primary);
      case EmailLogStatus.failed:
        return (Icons.error, context.colors.error);
      case EmailLogStatus.queued:
        return (Icons.hourglass_empty, context.colors.onSurfaceVariant);
    }
  }
}
