import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/features/audit/domain/audit_events.dart';
import 'package:myapp/features/audit/domain/audit_log_entry.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

/// Página `/audit-log` — lista los últimos eventos del usuario (login,
/// cambios de cuenta, MFA, passkey…). Append-only por RLS: el usuario
/// no puede modificar ni borrar.
class AuditLogPage extends ConsumerWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final entriesAsync = ref.watch(myAuditLogProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.accountSettings),
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
          constraints: const BoxConstraints(maxWidth: 720),
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
              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _AuditTile(entry: entries[i]),
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
      leading: Icon(_iconFor(entry.event), color: context.colors.primary),
      title: Text(_labelFor(l, entry.event)),
      subtitle: Text(formatter.format(entry.occurredAt.toLocal())),
      dense: true,
    );
  }

  IconData _iconFor(String event) {
    if (event.startsWith('auth.login')) return Icons.login;
    if (event == AuditEvents.logout) return Icons.logout;
    if (event.startsWith('mfa.')) return Icons.shield_outlined;
    if (event.startsWith('passkey.')) return Icons.fingerprint;
    if (event == AuditEvents.passwordChanged) return Icons.password_outlined;
    if (event == AuditEvents.emailChangeRequested) {
      return Icons.alternate_email;
    }
    return Icons.history;
  }

  String _labelFor(AppLocalizations l, String event) {
    return switch (event) {
      AuditEvents.loginPassword => l.auditEventLoginPassword,
      AuditEvents.loginOauth => l.auditEventLoginOauth,
      AuditEvents.loginPasskey => l.auditEventLoginPasskey,
      AuditEvents.loginMfaRecovery => l.auditEventLoginMfaRecovery,
      AuditEvents.logout => l.auditEventLogout,
      AuditEvents.passwordChanged => l.auditEventPasswordChanged,
      AuditEvents.emailChangeRequested => l.auditEventEmailChangeRequested,
      AuditEvents.mfaEnabled => l.auditEventMfaEnabled,
      AuditEvents.mfaDisabled => l.auditEventMfaDisabled,
      AuditEvents.passkeyAdded => l.auditEventPasskeyAdded,
      AuditEvents.passkeyRemoved => l.auditEventPasskeyRemoved,
      _ => event,
    };
  }
}
