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
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

import '../../application/subjects_providers.dart';
import '../../data/subjects_datasource.dart';
import '../../domain/subject.dart';
import '../util/file_picker_web.dart';

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

  /// Valida el índice (bloqueo definitivo): tras confirmar, ya no se podrá
  /// regenerar.
  Future<void> _validateIndex() async {
    if (_busy) return;
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.studyValidateConfirmTitle,
      body: l.studyValidateConfirmBody,
      confirmLabel: l.studyValidateIndex,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(subjectsDataSourceProvider)
          .validateIndex(widget.subject.id);
      ref.invalidate(subjectsListProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.studyIndexValidated)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.studyViewError)),
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
          // Índice "ready" pero vacío: permitir regenerar (salvo bloqueado).
          return PremiumCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(child: Text(l.studySelectNode)),
                if (!widget.subject.indexLocked)
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

        final locked = widget.subject.indexLocked;
        final aiNodeIds =
            ref.watch(aiContentNodeIdsProvider(widget.subject.id)).valueOrNull ??
                const <String>{};

        final tree = _IndexTree(
          nodes: ordered,
          selectedId: selectedId,
          aiNodeIds: aiNodeIds,
          locked: locked,
          onRegenerate: (_busy || locked) ? null : _generateIndex,
          onValidate: _busy ? null : _validateIndex,
          regenerating: _busy,
          onSelect: (id) => setState(() => _selectedNodeId = id),
        );
        final card = _CentralCard(
          nodeId: selectedId,
          subjectId: widget.subject.id,
        );

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

class _IndexTree extends StatefulWidget {
  const _IndexTree({
    required this.nodes,
    required this.selectedId,
    required this.aiNodeIds,
    required this.locked,
    required this.onSelect,
    required this.onRegenerate,
    required this.onValidate,
    required this.regenerating,
  });

  final List<IndexNode> nodes;
  final String selectedId;

  /// Nodos con contenido IA (explicado/resumen) -> se pintan en azul.
  final Set<String> aiNodeIds;

  /// Índice validado: sin botón de regenerar.
  final bool locked;
  final ValueChanged<String> onSelect;
  final VoidCallback? onRegenerate;
  final VoidCallback? onValidate;
  final bool regenerating;

  @override
  State<_IndexTree> createState() => _IndexTreeState();
}

class _IndexTreeState extends State<_IndexTree> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    // Por defecto expandimos solo los nodos raíz (depth 0).
    for (final n in widget.nodes) {
      if (n.parentId == null) _expanded.add(n.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;

    final byParent = <String?, List<IndexNode>>{};
    for (final n in widget.nodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.position.compareTo(b.position));
    }

    final rows = <Widget>[];
    void emit(IndexNode n) {
      final children = byParent[n.id] ?? const <IndexNode>[];
      final hasChildren = children.isNotEmpty;
      final isExpanded = _expanded.contains(n.id);
      rows.add(
        _TreeTile(
          node: n,
          hasChildren: hasChildren,
          hasAi: widget.aiNodeIds.contains(n.id),
          expanded: isExpanded,
          selected: n.id == widget.selectedId,
          onToggle: hasChildren
              ? () => setState(() {
                    if (isExpanded) {
                      _expanded.remove(n.id);
                    } else {
                      // Acordeón: al abrir un nodo cerramos sus hermanos, así
                      // el índice no ocupa tanto.
                      for (final s
                          in byParent[n.parentId] ?? const <IndexNode>[]) {
                        _expanded.remove(s.id);
                      }
                      _expanded.add(n.id);
                    }
                  })
              : null,
          onSelect: () => widget.onSelect(n.id),
        ),
      );
      if (hasChildren && isExpanded) {
        for (final c in children) {
          emit(c);
        }
      }
    }

    for (final root in byParent[null] ?? const <IndexNode>[]) {
      emit(root);
    }

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
                if (widget.locked)
                  Tooltip(
                    message: l.studyIndexValidated,
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: Icon(
                        Icons.verified_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ),
                  )
                else ...[
                  if (widget.regenerating)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  else ...[
                    IconButton(
                      tooltip: l.studyValidateIndex,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      onPressed: widget.onValidate,
                    ),
                    IconButton(
                      tooltip: l.studyRegenerate,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: widget.onRegenerate,
                    ),
                  ],
                ],
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

/// Una fila del árbol: chevron (si tiene hijos) + título. El chevron expande/
/// contrae; el título selecciona el nodo.
class _TreeTile extends StatelessWidget {
  const _TreeTile({
    required this.node,
    required this.hasChildren,
    required this.hasAi,
    required this.expanded,
    required this.selected,
    required this.onToggle,
    required this.onSelect,
  });

  final IndexNode node;
  final bool hasChildren;

  /// `true` si este nodo ya tiene Explicado/Resumen generado -> texto azul.
  final bool hasAi;
  final bool expanded;
  final bool selected;
  final VoidCallback? onToggle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return InkWell(
      onTap: onSelect,
      child: ColoredBox(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.sm + node.depth * 14.0,
            right: AppSpacing.sm,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: hasChildren
                    ? InkWell(
                        onTap: onToggle,
                        borderRadius: BorderRadius.circular(12),
                        child: Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : null,
              ),
              // Tipo de nodo: carpeta si tiene hijos, punto si es hoja.
              Icon(
                hasChildren ? Icons.folder_outlined : Icons.fiber_manual_record,
                size: hasChildren ? 16 : 8,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: (selected || node.parentId == null)
                        ? FontWeight.w700
                        : FontWeight.w500,
                    // Azul = ya tiene contenido IA (explicado/resumen). La
                    // selección se distingue por el fondo resaltado + negrita.
                    color: hasAi ? scheme.primary : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card central con 3 pestañas para el nodo seleccionado.
class _CentralCard extends StatelessWidget {
  const _CentralCard({
    required this.nodeId,
    required this.subjectId,
  });

  final String nodeId;
  final String subjectId;

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
                  _NodeView(
                    nodeId: nodeId,
                    kind: 'original',
                    subjectId: subjectId,
                  ),
                  _NodeView(
                    nodeId: nodeId,
                    kind: 'explained',
                    subjectId: subjectId,
                  ),
                  _NodeView(
                    nodeId: nodeId,
                    kind: 'summary',
                    subjectId: subjectId,
                  ),
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
  const _NodeView({
    required this.nodeId,
    required this.kind,
    required this.subjectId,
  });

  final String nodeId;
  final String kind;
  final String subjectId;

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
      // El backend genera Explicado y Resumen a la vez: refrescamos ambas
      // vistas y la marca azul del índice.
      ref.invalidate(
        nodeContentProvider((nodeId: widget.nodeId, kind: 'explained')),
      );
      ref.invalidate(
        nodeContentProvider((nodeId: widget.nodeId, kind: 'summary')),
      );
      ref.invalidate(aiContentNodeIdsProvider(widget.subjectId));
    } on SubjectsException catch (e) {
      final detail = e.detail != null && e.detail!.isNotEmpty
          ? ': ${e.detail}'
          : '';
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          duration: const Duration(seconds: 8),
          content: Text('${l.studyViewError} (${e.code})$detail'),
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

  /// Raíz + Original: abre el documento original tal cual (PDF/imagen) en una
  /// pestaña nueva, en vez de generar texto (el documento completo no cabría
  /// en una sola respuesta del modelo).
  Future<void> _openOriginal() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      final url = await ref
          .read(subjectsDataSourceProvider)
          .originalDocumentUrl(widget.subjectId);
      if (url != null) {
        openUrlInNewTab(url);
      } else {
        messenger.showSnackBar(
          SnackBar(backgroundColor: errBg, content: Text(l.studyViewError)),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.studyViewError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(nodeContentProvider(_key));
    final isOriginal = widget.kind == 'original';

    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => AppErrorState(
        message: l.studyViewError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(nodeContentProvider(_key)),
        retryLabel: l.actionRetry,
      ),
      data: (content) {
        final hasContent = content != null && content.isNotEmpty;

        // ORIGINAL: nunca usa IA. Muestra el texto guardado; si no lo hay,
        // ofrece abrir el documento original (PDF).
        if (isOriginal) {
          if (hasContent) return _scroll(context, content);
          return Center(
            child: PremiumButton(
              label: l.studyOpenOriginal,
              leadingIcon: Icons.open_in_new,
              loading: _busy,
              onPressed: _busy ? null : _openOriginal,
            ),
          );
        }

        // EXPLICADO / RESUMEN: generación bajo demanda.
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
        if (!hasContent) {
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
            Expanded(child: _scroll(context, content)),
          ],
        );
      },
    );
  }

  Widget _scroll(BuildContext context, String content) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: SelectableText(
        content,
        style: context.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
    );
  }
}
