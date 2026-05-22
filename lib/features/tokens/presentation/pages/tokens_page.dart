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
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../../application/tokens_providers.dart';
import '../../domain/personal_access_token.dart';
import '../widgets/create_token_dialog.dart';
import '../widgets/token_secret_dialog.dart';

/// `/account-settings/tokens` — lista los PAT del usuario y permite
/// crearlos/revocarlos. Diseño calcado de GitHub: cada item muestra
/// solo el prefix (`pat_xxxxxxxx`) + nombre + scopes + caducidad +
/// último uso. El secret completo SOLO se ve una vez al crear.
class TokensPage extends ConsumerStatefulWidget {
  const TokensPage({super.key});

  @override
  ConsumerState<TokensPage> createState() => _TokensPageState();
}

class _TokensPageState extends ConsumerState<TokensPage> {
  int _page = 0;
  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(userTokensProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.accountSettings),
        ),
        title: Text(l.tokensTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(userTokensProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.tokensCreate),
        onPressed: _onCreate,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: async.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.tokensLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(userTokensProvider),
              retryLabel: l.actionRetry,
            ),
            data: (tokens) {
              if (tokens.isEmpty) {
                return AppEmptyState(
                  icon: Icons.vpn_key_outlined,
                  title: l.tokensEmptyTitle,
                  message: l.tokensEmptyBody,
                );
              }
              final totalPages = (tokens.length / _pageSize).ceil();
              final page = _page.clamp(0, totalPages - 1);
              final start = page * _pageSize;
              final end = (start + _pageSize) > tokens.length
                  ? tokens.length
                  : start + _pageSize;
              final pageTokens = tokens.sublist(start, end);
              return Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      // +1 por el _IntroCard fijo en la posición 0.
                      itemCount: pageTokens.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        if (i == 0) return _IntroCard(l: l);
                        return _TokenTile(token: pageTokens[i - 1]);
                      },
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

  Future<void> _onCreate() async {
    final l = context.l10n;
    final result = await showDialog<PersonalAccessToken>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateTokenDialog(),
    );
    if (result == null || !mounted) return;
    ref.invalidate(userTokensProvider);
    // Inmediatamente mostramos el secret en otro dialog -- una sola vez.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TokenSecretDialog(token: result),
    );
    if (!mounted) return;
    context.showSnack(l.tokensCreated(result.name));
  }
}

/// Banner explicativo en la cabecera. Recuerda al user que el secret
/// solo se ve una vez y que estos tokens dan acceso a la API.
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: context.colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: context.colors.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.tokensIntro,
                style: context.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenTile extends ConsumerStatefulWidget {
  const _TokenTile({required this.token});
  final PersonalAccessToken token;

  @override
  ConsumerState<_TokenTile> createState() => _TokenTileState();
}

class _TokenTileState extends ConsumerState<_TokenTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode);
    final t = widget.token;
    final isInactive = t.isRevoked || t.isExpired;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              isInactive
                  ? Icons.vpn_key_off_outlined
                  : Icons.vpn_key_outlined,
              color: isInactive
                  ? context.colors.onSurfaceVariant
                  : context.colors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.name,
                          style: context.textTheme.titleSmall?.copyWith(
                            color: isInactive
                                ? context.colors.onSurfaceVariant
                                : null,
                            decoration: t.isRevoked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (t.isRevoked)
                        _StatusChip(
                          label: l.tokensStatusRevoked,
                          color: context.colors.error,
                        )
                      else if (t.isExpired)
                        _StatusChip(
                          label: l.tokensStatusExpired,
                          color: context.colors.error,
                        )
                      else
                        _StatusChip(
                          label: l.tokensStatusActive,
                          color: context.colors.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Línea técnica: prefix (mono) + scopes.
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        t.prefix,
                        style: context.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      for (final s in t.scopes)
                        _ScopeChip(scope: s, l: l),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _metaLine(l, fmt, t),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!t.isRevoked)
              IconButton(
                tooltip: l.tokensRevoke,
                icon: const Icon(Icons.block),
                onPressed: _busy ? null : _onRevoke,
              )
            else
              IconButton(
                tooltip: l.tokensDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : _onDelete,
              ),
          ],
        ),
      ),
    );
  }

  String _metaLine(
    AppLocalizations l,
    DateFormat fmt,
    PersonalAccessToken t,
  ) {
    final parts = <String>[
      l.tokensCreatedAt(fmt.format(t.createdAt.toLocal())),
    ];
    if (t.expiresAt != null) {
      parts.add(l.tokensExpiresAt(fmt.format(t.expiresAt!.toLocal())));
    } else {
      parts.add(l.tokensNeverExpires);
    }
    if (t.lastUsedAt != null) {
      parts.add(l.tokensLastUsed(fmt.format(t.lastUsedAt!.toLocal())));
    } else {
      parts.add(l.tokensNeverUsed);
    }
    if (t.revokedAt != null) {
      parts.add(l.tokensRevokedAt(fmt.format(t.revokedAt!.toLocal())));
    }
    return parts.join(' • ');
  }

  Future<void> _onRevoke() async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.tokensRevokeConfirmTitle,
      body: l.tokensRevokeConfirmBody(widget.token.name),
      confirmLabel: l.tokensRevoke,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(tokensDataSourceProvider).revoke(widget.token.id);
      if (!mounted) return;
      ref.invalidate(userTokensProvider);
      context.showSnack(l.tokensRevoked);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.tokensRevokeError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onDelete() async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.tokensDeleteConfirmTitle,
      body: l.tokensDeleteConfirmBody(widget.token.name),
      confirmLabel: l.tokensDelete,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(tokensDataSourceProvider).delete(widget.token.id);
      if (!mounted) return;
      ref.invalidate(userTokensProvider);
      context.showSnack(l.tokensDeleted);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.tokensDeleteError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.scope, required this.l});
  final String scope;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final isWrite = scope == 'write';
    final color = isWrite ? context.colors.tertiary : context.colors.secondary;
    final label = isWrite ? l.tokensScopeWrite : l.tokensScopeRead;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
