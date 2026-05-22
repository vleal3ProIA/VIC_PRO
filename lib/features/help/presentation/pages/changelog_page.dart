import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../application/changelog_providers.dart';
import '../../domain/changelog_entry.dart';
import '../widgets/changelog_category_visuals.dart';

/// `/changelog` — "What's new" público. Solo lista entradas publicadas.
/// Al entrar marca `changelog_seen_at = now()` -> el badge rojo del
/// AppBar desaparece tras la siguiente carga.
class ChangelogPage extends ConsumerStatefulWidget {
  const ChangelogPage({super.key});

  @override
  ConsumerState<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends ConsumerState<ChangelogPage> {
  @override
  void initState() {
    super.initState();
    // Disparamos mark_seen al entrar (best-effort, fire-and-forget).
    // Cuando vuelva, invalidamos el provider del badge para que el
    // icono "?" del AppBar se refresque.
    Future.microtask(() async {
      try {
        await ref.read(changelogDataSourceProvider).markSeen();
        if (!mounted) return;
        ref.invalidate(hasUnseenChangelogProvider);
      } catch (_) {
        // Silencioso — si falla, en la próxima visita lo reintenta.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(changelogEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.home),
        ),
        title: Text(l.changelogTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(changelogEntriesProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: double.infinity),
          child: async.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.changelogLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(changelogEntriesProvider),
              retryLabel: l.actionRetry,
            ),
            data: (entries) {
              // En la vista USER filtramos drafts (admin sí los ve aquí,
              // pero su flujo de gestión está en /admin/changelog).
              final published = entries.where((e) => e.isPublished).toList();
              if (published.isEmpty) {
                return AppEmptyState(
                  icon: Icons.campaign_outlined,
                  title: l.changelogEmptyTitle,
                  message: l.changelogEmptyBody,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                itemCount: published.length,
                itemBuilder: (_, i) => _EntryCard(entry: published[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});
  final ChangelogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode);
    final v = visualsFor(context, entry.category);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera: icono + categoría chip + fecha + version (si).
            Row(
              children: [
                Icon(v.icon, color: v.color, size: 22),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: v.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    v.label(l),
                    style: context.textTheme.labelSmall?.copyWith(
                      color: v.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (entry.version != null) ...[
                  Text(
                    entry.version!,
                    style: context.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  fmt.format(entry.publishedAt!.toLocal()),
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Title.
            Text(
              entry.title,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            // Body (texto plano por simplicidad; markdown rendering
            // podemos añadirlo en una PR posterior si los users lo piden).
            SelectableText(
              entry.body,
              style: context.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
