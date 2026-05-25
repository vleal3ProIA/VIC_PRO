// ============================================================================
// CollapsibleIndexTree · Árbol del índice en SOLO LECTURA con carpetas
// plegables, con el mismo aspecto que la card del índice (carpeta amarilla en
// negrita + chevron, hoja con punto). Acordeón por nivel: al abrir una carpeta
// se cierran sus hermanas, para que un índice largo no ocupe demasiado. Arranca
// con el primer nivel (raíz) desplegado. Se usa en los modales de revisión del
// índice (asistente de subida y revisión del panel).
// ============================================================================

import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';

import '../../domain/subject.dart';

class CollapsibleIndexTree extends StatefulWidget {
  const CollapsibleIndexTree({required this.nodes, super.key});

  final List<IndexNode> nodes;

  @override
  State<CollapsibleIndexTree> createState() => _CollapsibleIndexTreeState();
}

class _CollapsibleIndexTreeState extends State<CollapsibleIndexTree> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    for (final n in widget.nodes) {
      if (n.parentId == null) _expanded.add(n.id);
    }
  }

  @override
  Widget build(BuildContext context) {
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
      final isOpen = _expanded.contains(n.id);
      rows.add(_row(context, n, byParent, hasChildren: hasChildren, open: isOpen));
      if (hasChildren && isOpen) {
        for (final c in children) {
          emit(c);
        }
      }
    }

    for (final r in byParent[null] ?? const <IndexNode>[]) {
      emit(r);
    }
    return Scrollbar(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        children: rows,
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IndexNode n,
    Map<String?, List<IndexNode>> byParent, {
    required bool hasChildren,
    required bool open,
  }) {
    final scheme = context.colors;
    void toggle() {
      setState(() {
        if (open) {
          _expanded.remove(n.id);
        } else {
          // Acordeón: al abrir una carpeta, cerramos sus hermanas del mismo nivel.
          for (final s in byParent[n.parentId] ?? const <IndexNode>[]) {
            _expanded.remove(s.id);
          }
          _expanded.add(n.id);
        }
      });
    }

    return InkWell(
      onTap: hasChildren ? toggle : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.sm + n.depth * 14.0,
          right: AppSpacing.sm,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: hasChildren
                  ? Icon(
                      open ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    )
                  : null,
            ),
            Icon(
              hasChildren ? Icons.folder_rounded : Icons.fiber_manual_record,
              size: hasChildren ? 17 : 10,
              color: hasChildren ? Colors.amber.shade700 : scheme.onSurface,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                n.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: hasChildren ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
