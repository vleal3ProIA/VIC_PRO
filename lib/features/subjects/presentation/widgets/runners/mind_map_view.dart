// ============================================================================
// subjects · MindMapView — mapa mental navegable del índice
// ----------------------------------------------------------------------------
// Render del índice del temario como un mapa mental interactivo: nodos en
// burbujas conectadas por líneas, con zoom/pan via [InteractiveViewer],
// expandir/colapsar ramas y resaltar el nodo seleccionado. Al pulsar una
// burbuja llama a [onSelectNode] para sincronizar con el contexto que lo
// invoque (en el Panel: scroll del índice; en Mi Material: no-op u otra).
//
// Extraído de `subject_study_panel.dart` (antes `_MindMapView` privado).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../../application/subjects_providers.dart';
import '../../../domain/subject.dart';

/// Mapa mental navegable de los nodos del índice de un temario.
class MindMapView extends ConsumerStatefulWidget {
  const MindMapView({
    required this.subjectId,
    required this.selectedId,
    required this.onSelectNode,
    super.key,
  });

  final String subjectId;
  final String? selectedId;
  final ValueChanged<String> onSelectNode;

  @override
  ConsumerState<MindMapView> createState() => _MindMapViewState();
}

class _MindMapViewState extends ConsumerState<MindMapView> {
  final Set<String> _expanded = {};
  final _tc = TransformationController();
  bool _init = false;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(indexNodesProvider(widget.subjectId));
    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => AppErrorState(
        message: l.studyViewError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(indexNodesProvider(widget.subjectId)),
        retryLabel: l.actionRetry,
      ),
      data: (nodes) {
        if (nodes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                l.studioMindmapEmpty,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ),
          );
        }

        final byParent = <String?, List<IndexNode>>{};
        for (final n in nodes) {
          byParent.putIfAbsent(n.parentId, () => []).add(n);
        }
        for (final list in byParent.values) {
          list.sort((a, b) => a.position.compareTo(b.position));
        }

        if (!_init) {
          _init = true;
          final byId = {for (final n in nodes) n.id: n};
          for (final n in nodes) {
            if (n.parentId == null) _expanded.add(n.id);
          }
          // Expande el camino hasta el nodo seleccionado.
          var cur = widget.selectedId != null ? byId[widget.selectedId] : null;
          while (cur != null && cur.parentId != null) {
            _expanded.add(cur.parentId!);
            cur = byId[cur.parentId];
          }
        }

        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _tc,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(400),
              minScale: 0.3,
              maxScale: 2.5,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final root in byParent[null] ?? const <IndexNode>[])
                      _branch(context, root, byParent, isRoot: true),
                  ],
                ),
              ),
            ),
            Positioned(
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: Material(
                elevation: 1,
                shape: const CircleBorder(),
                color: context.colors.surface,
                child: IconButton(
                  tooltip: l.studioMindmapReset,
                  icon: const Icon(Icons.center_focus_strong, size: 20),
                  onPressed: () => _tc.value = Matrix4.identity(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _branch(
    BuildContext context,
    IndexNode node,
    Map<String?, List<IndexNode>> byParent, {
    required bool isRoot,
  }) {
    final children = byParent[node.id] ?? const <IndexNode>[];
    final hasChildren = children.isNotEmpty;
    final expanded = _expanded.contains(node.id);
    final bubble = _bubble(context, node, hasChildren: hasChildren, expanded: expanded);

    if (!hasChildren || !expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [if (!isRoot) _stub(context), bubble],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!isRoot) _stub(context),
          bubble,
          _stub(context),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: context.colors.outlineVariant),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in children)
                  _branch(context, c, byParent, isRoot: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stub(BuildContext context) => SizedBox(
        width: 18,
        child: Divider(height: 2, thickness: 2, color: context.colors.outlineVariant),
      );

  Widget _bubble(
    BuildContext context,
    IndexNode node, {
    required bool hasChildren,
    required bool expanded,
  }) {
    final scheme = context.colors;
    final selected = node.id == widget.selectedId;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.16)
        : (node.depth == 0
            ? scheme.primary.withValues(alpha: 0.07)
            : Colors.transparent);
    return InkWell(
      onTap: () => widget.onSelectNode(node.id),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                node.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: node.depth == 0 ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? scheme.primary : null,
                ),
              ),
            ),
            if (hasChildren)
              InkWell(
                onTap: () => setState(() {
                  if (expanded) {
                    _expanded.remove(node.id);
                  } else {
                    _expanded.add(node.id);
                  }
                }),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    expanded ? Icons.remove_circle_outline : Icons.add_circle_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
