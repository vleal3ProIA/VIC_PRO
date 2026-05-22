import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_pagination_bar.dart';

import '../../application/auth_sessions_providers.dart';
import '../../domain/auth_session.dart';

/// `/account-settings/sessions` — lista las sesiones activas del usuario
/// (cada login en un dispositivo/navegador) y permite revocarlas.
///
/// La sesión actual aparece marcada y sin botón de revocar individual:
/// para cerrar la actual, el usuario debe ir al menú de logout normal.
/// El botón global "Cerrar todas las demás" sí está disponible siempre.
class AccountSessionsPage extends ConsumerWidget {
  const AccountSessionsPage({super.key});

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
        title: Text(l.sessionsTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(authSessionsProvider),
          ),
        ],
      ),
      body: const SessionsView(),
    );
  }
}

/// Cuerpo de la lista de sesiones (sin Scaffold). Reutilizable como página
/// completa o embebido en el master-detail de Ajustes → Seguridad.
class SessionsView extends ConsumerStatefulWidget {
  const SessionsView({this.embedded = false, super.key});

  /// `true` cuando se embebe dentro de otro scroll (master-detail de Ajustes):
  /// usa `shrinkWrap` en lugar de `Expanded` para no requerir altura acotada.
  final bool embedded;

  @override
  ConsumerState<SessionsView> createState() => _SessionsViewState();
}

class _SessionsViewState extends ConsumerState<SessionsView> {
  int _page = 0;
  static const int _pageSize = 8;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(authSessionsProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: async.when(
          loading: () => const AppLoadingState(),
          error: (e, _) => AppErrorState(
            message: l.sessionsLoadError,
            detail: e.toString(),
            onRetry: () => ref.invalidate(authSessionsProvider),
            retryLabel: l.actionRetry,
          ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return AppEmptyState(
                icon: Icons.devices_outlined,
                message: l.sessionsEmpty,
              );
            }
            // Paginación client-side. El _Header muestra el total real
            // (todas las sesiones), pero la lista pagina de [_pageSize].
            final totalPages = (sessions.length / _pageSize).ceil();
            final page = _page.clamp(0, totalPages - 1);
            final start = page * _pageSize;
            final end = (start + _pageSize) > sessions.length
                ? sessions.length
                : start + _pageSize;
            final pageSessions = sessions.sublist(start, end);
            final list = ListView(
              padding: const EdgeInsets.all(16),
              shrinkWrap: widget.embedded,
              physics: widget.embedded
                  ? const NeverScrollableScrollPhysics()
                  : null,
              children: [
                _Header(sessions: sessions),
                const SizedBox(height: 16),
                for (final s in pageSessions) ...[
                  _SessionCard(session: s),
                  const SizedBox(height: 8),
                ],
              ],
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

class _Header extends ConsumerStatefulWidget {
  const _Header({required this.sessions});
  final List<AuthSession> sessions;

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final othersCount = widget.sessions.where((s) => !s.isCurrent).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.devices_outlined,
              color: context.colors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.sessionsCount(widget.sessions.length),
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (othersCount > 0)
                    Text(
                      l.sessionsOtherDevicesHint,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (othersCount > 0)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.logout, size: 18),
                label: Text(l.sessionsRevokeOthers),
                onPressed: _busy ? null : _onRevokeOthers,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onRevokeOthers() async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.sessionsRevokeOthersConfirmTitle,
      body: l.sessionsRevokeOthersConfirmBody,
      confirmLabel: l.sessionsRevokeOthers,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final count = await ref
          .read(authSessionsDataSourceProvider)
          .revokeOthers();
      if (!mounted) return;
      ref.invalidate(authSessionsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.sessionsRevokedOthers(count))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.sessionsRevokeError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SessionCard extends ConsumerStatefulWidget {
  const _SessionCard({required this.session});
  final AuthSession session;

  @override
  ConsumerState<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<_SessionCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMMd(localeCode).add_Hm();
    final ua = _UserAgentInfo.parse(widget.session.userAgent);
    final lastActiveAt = widget.session.updatedAt ?? widget.session.createdAt;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.session.isCurrent
              ? context.colors.primary
              : context.colors.outlineVariant,
          width: widget.session.isCurrent ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(ua.icon, size: 32, color: context.colors.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          ua.label,
                          style: context.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (widget.session.isCurrent) ...[
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(l.sessionsCurrentBadge),
                          backgroundColor: context.colors.primaryContainer,
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                      if ((widget.session.aal ?? 'aal1') == 'aal2') ...[
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(l.sessionsMfaBadge),
                          backgroundColor: context.colors.tertiaryContainer,
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.sessionsLastActive(fmt.format(lastActiveAt.toLocal())),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  if (widget.session.ip != null)
                    Text(
                      l.sessionsIp(widget.session.ip!),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (!widget.session.isCurrent)
              IconButton(
                tooltip: l.sessionsRevoke,
                icon: const Icon(Icons.logout),
                onPressed: _busy ? null : _onRevoke,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onRevoke() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref
          .read(authSessionsDataSourceProvider)
          .revoke(widget.session.id);
      if (!mounted) return;
      ref.invalidate(authSessionsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.sessionsRevoked)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.sessionsRevokeError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Heurística MUY simple para sacar nombre legible + icono del User-
/// Agent. No usa una librería externa — un puñado de `contains` cubre
/// el 95% de navegadores modernos y los desconocidos caen en "Unknown".
class _UserAgentInfo {
  const _UserAgentInfo(this.label, this.icon);

  factory _UserAgentInfo.parse(String? ua) {
    if (ua == null || ua.isEmpty) {
      return const _UserAgentInfo('Unknown device', Icons.help_outline);
    }
    final lower = ua.toLowerCase();
    IconData icon;
    if (lower.contains('iphone')) {
      icon = Icons.phone_iphone;
    } else if (lower.contains('ipad')) {
      icon = Icons.tablet_mac;
    } else if (lower.contains('android')) {
      icon = lower.contains('mobile') ? Icons.smartphone : Icons.tablet_android;
    } else if (lower.contains('mac os') || lower.contains('macintosh')) {
      icon = Icons.laptop_mac;
    } else if (lower.contains('windows')) {
      icon = Icons.desktop_windows;
    } else if (lower.contains('linux') || lower.contains('x11')) {
      icon = Icons.computer;
    } else {
      icon = Icons.devices_other;
    }

    String browser = 'Browser';
    if (lower.contains('edg/')) {
      browser = 'Edge';
    } else if (lower.contains('chrome/') && !lower.contains('chromium/')) {
      browser = 'Chrome';
    } else if (lower.contains('firefox/')) {
      browser = 'Firefox';
    } else if (lower.contains('safari/') && !lower.contains('chrome/')) {
      browser = 'Safari';
    } else if (lower.contains('opera/') || lower.contains('opr/')) {
      browser = 'Opera';
    }

    String os = 'Unknown OS';
    if (lower.contains('windows nt')) {
      os = 'Windows';
    } else if (lower.contains('mac os') || lower.contains('macintosh')) {
      os = 'macOS';
    } else if (lower.contains('iphone os') || lower.contains('iphone')) {
      os = 'iOS';
    } else if (lower.contains('android')) {
      os = 'Android';
    } else if (lower.contains('linux')) {
      os = 'Linux';
    }

    return _UserAgentInfo('$browser · $os', icon);
  }

  final String label;
  final IconData icon;
}
