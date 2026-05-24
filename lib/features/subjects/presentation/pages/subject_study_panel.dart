// ============================================================================
// subjects · Panel de estudio (Fase 2) — índice + card central de 3 pestañas
// ----------------------------------------------------------------------------
// Se monta bajo el panel de documentos. Si el índice no está generado, ofrece
// "Generar índice" (con polling de subjects.index_status). Cuando está listo,
// muestra el árbol del índice y, para el nodo seleccionado, una card con 3
// pestañas (Original / Explicado / Resumen) que se generan bajo demanda vía
// generate-views y se cachean.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/subjects_providers.dart';
import '../../data/subjects_datasource.dart';
import '../../domain/subject.dart';

class SubjectStudyPanel extends ConsumerStatefulWidget {
  const SubjectStudyPanel({required this.subject, super.key});

  final Subject subject;

  @override
  ConsumerState<SubjectStudyPanel> createState() => _SubjectStudyPanelState();
}

class _SubjectStudyPanelState extends ConsumerState<SubjectStudyPanel> {
  Timer? _poll;
  bool _busy = false;
  String? _selectedNodeId;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPolling(bool generating) {
    if (generating) {
      _poll ??= Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) {
          _poll?.cancel();
          _poll = null;
          return;
        }
        ref.invalidate(subjectsListProvider);
      });
    } else if (_poll != null) {
      _poll!.cancel();
      _poll = null;
      // Recién terminó: refresca el árbol del índice tras el frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(indexNodesProvider(widget.subject.id));
      });
    }
  }

  Future<void> _generateIndex() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(subjectsDataSourceProvider)
          .generateIndex(widget.subject.id);
      ref.invalidate(subjectsListProvider);
    } on SubjectsException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.studyIndexFailed} (${e.code})'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text(l.studyIndexFailed),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncPolling(widget.subject.indexGenerating);
    final l = context.l10n;

    // Estado del índice: generating / ready / (none|failed).
    if (widget.subject.indexGenerating) {
      return PremiumCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.studyIndexGenerating,
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(6)),
              child: LinearProgressIndicator(minHeight: 4),
            ),
          ],
        ),
      );
    }

    if (!widget.subject.indexReady) {
      // none o failed -> ofrecer generar (si hay documentos 'ready').
      final docsAsync = ref.watch(subjectDocumentsProvider(widget.subject.id));
      final hasReady =
          docsAsync.valueOrNull?.any((d) => d.status == DocStatus.ready) ??
              false;
      return PremiumCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.account_tree_outlined, color: context.colors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                widget.subject.indexStatus == IndexStatus.failed
                    ? l.studyIndexFailed
                    : (hasReady ? l.studyIndexTitle : l.studyIndexNeedsDoc),
                style: context.textTheme.bodyMedium,
              ),
            ),
            PremiumButton(
              label: l.studyGenerateIndex,
              leadingIcon: Icons.auto_awesome_outlined,
              loading: _busy,
              onPressed: (_busy || !hasReady) ? null : _generateIndex,
            ),
          ],
        ),
      );
    }

    // ready -> índice + card central.
    final nodesAsync = ref.watch(indexNodesProvider(widget.subject.id));
    return nodesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: AppLoadingState(),
      ),
      error: (e, _) => AppErrorState(
        message: l.studyViewError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(indexNodesProvider(widget.subject.id)),
        retryLabel: l.actionRetry,
      ),
      data: (nodes) {
        if (nodes.isEmpty) {
          // Índice "ready" pero vacío: permitir regenerar.
          return PremiumCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(child: Text(l.studySelectNode)),
                PremiumButton(
                  label: l.studyGenerateIndex,
                  loading: _busy,
                  onPressed: _busy ? null : _generateIndex,
                ),
              ],
            ),
          );
        }
        final ordered = _dfs(nodes);
        final selectedId = ordered.any((n) => n.id == _selectedNodeId)
            ? _selectedNodeId!
            : ordered.first.id;

        final tree = _IndexTree(
          nodes: ordered,
          selectedId: selectedId,
          onRegenerate: _busy ? null : _generateIndex,
          regenerating: _busy,
          onSelect: (id) => setState(() => _selectedNodeId = id),
        );
        final card = _CentralCard(nodeId: selectedId);

        return LayoutBuilder(
          builder: (ctx, c) {
            if (c.maxWidth >= 820) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 300, child: tree),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: card),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [tree, const SizedBox(height: AppSpacing.md), card],
            );
          },
        );
      },
    );
  }

  /// Ordena los nodos en recorrido DFS (para indentar el árbol).
  List<IndexNode> _dfs(List<IndexNode> all) {
    final byParent = <String?, List<IndexNode>>{};
    for (final n in all) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.position.compareTo(b.position));
    }
    final out = <IndexNode>[];
    void visit(String? parent) {
      for (final n in byParent[parent] ?? const <IndexNode>[]) {
        out.add(n);
        visit(n.id);
      }
    }

    visit(null);
    return out;
  }
}

class _IndexTree extends StatelessWidget {
  const _IndexTree({
    required this.nodes,
    required this.selectedId,
    required this.onSelect,
    required this.onRegenerate,
    required this.regenerating,
  });

  final List<IndexNode> nodes;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback? onRegenerate;
  final bool regenerating;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    return PremiumCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.studyIndexTitle,
                    style: context.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l.studyRegenerate,
                  visualDensity: VisualDensity.compact,
                  icon: regenerating
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  onPressed: onRegenerate,
                ),
              ],
            ),
          ),
          for (final n in nodes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(
                left: AppSpacing.md + n.depth * 14.0,
                right: AppSpacing.sm,
              ),
              title: Text(
                n.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight:
                      n.id == selectedId ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              selected: n.id == selectedId,
              selectedTileColor: scheme.primary.withValues(alpha: 0.10),
              onTap: () => onSelect(n.id),
            ),
        ],
      ),
    );
  }
}

/// Card central con 3 pestañas para el nodo seleccionado.
class _CentralCard extends StatelessWidget {
  const _CentralCard({required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: DefaultTabController(
        length: 3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              tabs: [
                Tab(text: l.studyTabOriginal),
                Tab(text: l.studyTabExplained),
                Tab(text: l.studyTabSummary),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 460,
              child: TabBarView(
                children: [
                  _NodeView(nodeId: nodeId, kind: 'original'),
                  _NodeView(nodeId: nodeId, kind: 'explained'),
                  _NodeView(nodeId: nodeId, kind: 'summary'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una pestaña: muestra la vista cacheada o un botón para generarla.
class _NodeView extends ConsumerStatefulWidget {
  const _NodeView({required this.nodeId, required this.kind});

  final String nodeId;
  final String kind;

  @override
  ConsumerState<_NodeView> createState() => _NodeViewState();
}

class _NodeViewState extends ConsumerState<_NodeView> {
  bool _busy = false;

  NodeViewKey get _key => (nodeId: widget.nodeId, kind: widget.kind);

  Future<void> _generate({bool force = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref.read(subjectsDataSourceProvider).generateView(
            nodeId: widget.nodeId,
            kind: widget.kind,
            force: force,
          );
      ref.invalidate(nodeContentProvider(_key));
    } on SubjectsException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.studyViewError} (${e.code})'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text(l.studyViewError),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(nodeContentProvider(_key));

    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => AppErrorState(
        message: l.studyViewError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(nodeContentProvider(_key)),
        retryLabel: l.actionRetry,
      ),
      data: (content) {
        if (_busy) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.sm),
                Text(l.studyGenerating, style: context.textTheme.bodySmall),
              ],
            ),
          );
        }
        if (content == null || content.isEmpty) {
          return Center(
            child: PremiumButton(
              label: l.studyGenerateView,
              leadingIcon: Icons.auto_awesome_outlined,
              onPressed: _generate,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _generate(force: true),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(l.studyRegenerate),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: SelectableText(
                  content,
                  style: context.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
