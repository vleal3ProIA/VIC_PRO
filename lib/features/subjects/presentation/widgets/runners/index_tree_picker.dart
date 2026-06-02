// ============================================================================
// subjects · IndexTreePicker
// ----------------------------------------------------------------------------
// Selector jerarquico de secciones del indice (Titulo > Capitulo > Articulo)
// para los configuradores de test (mock_exam, tf, etc).
//
// Caracteristicas:
//   - Vista accordeon en el nivel raiz (solo un Titulo/Disposicion expandido
//     a la vez) para no ocupar la pantalla entera con el indice plano.
//   - Niveles inferiores libremente expandibles.
//   - Checkbox tri-state en padres (vacio/parcial/lleno).
//   - Cascada: marcar un padre marca todos sus descendientes; desmarcar uno
//     los desmarca a todos.
//   - El usuario puede expandir un padre y desmarcar hijos sueltos: el padre
//     pasa a "parcial".
//
// El widget mantiene su estado interno y notifica al padre via
// [onSelectionChanged] cada vez que cambia el Set de ids seleccionados.
// ============================================================================

import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';

import '../../../domain/subject.dart';

/// Estado de selección de un nodo padre.
enum _TriState { none, partial, all }

class IndexTreePicker extends StatefulWidget {
  const IndexTreePicker({
    required this.nodes,
    required this.selected,
    required this.onSelectionChanged,
    super.key,
  });

  /// TODOS los nodos del subject (incluida la raíz). El widget filtra
  /// internamente: la raíz NO se muestra (es implícita = "Todo"), pero sus
  /// hijos directos (Títulos, Disposiciones) se muestran como nivel root.
  final List<IndexNode> nodes;

  /// Conjunto inicial de ids seleccionados. El widget lo copia y muta.
  final Set<String> selected;

  /// Notificado cada vez que cambia la selección. La Set entregada es una
  /// copia que el llamante puede almacenar/leer sin riesgos.
  final ValueChanged<Set<String>> onSelectionChanged;

  @override
  State<IndexTreePicker> createState() => _IndexTreePickerState();
}

class _IndexTreePickerState extends State<IndexTreePicker> {
  late Set<String> _selected;

  /// Hijos directos de cada nodo (id -> List<IndexNode>).
  late Map<String?, List<IndexNode>> _childrenByParent;

  /// Cache de descendientes (id -> Set de ids descendientes, incluido el
  /// propio nodo). Se computa una vez al iniciar.
  late Map<String, Set<String>> _descendantsByNode;

  /// Id del Título raíz actualmente expandido (accordeon). null = ninguno.
  String? _expandedRootId;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selected};
    _buildIndex();
  }

  @override
  void didUpdateWidget(covariant IndexTreePicker old) {
    super.didUpdateWidget(old);
    if (!_setEq(old.selected, widget.selected)) {
      _selected = {...widget.selected};
    }
    if (old.nodes != widget.nodes) {
      _buildIndex();
    }
  }

  static bool _setEq(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }

  void _buildIndex() {
    _childrenByParent = <String?, List<IndexNode>>{};
    for (final n in widget.nodes) {
      _childrenByParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    // Ordenar cada lista por (depth, position) — la mayoría ya vienen ordenadas
    // de la BD, pero esto las consolida.
    for (final list in _childrenByParent.values) {
      list.sort((a, b) {
        final byDepth = a.depth.compareTo(b.depth);
        if (byDepth != 0) return byDepth;
        return a.position.compareTo(b.position);
      });
    }

    _descendantsByNode = <String, Set<String>>{};
    for (final n in widget.nodes) {
      _descendantsByNode[n.id] = _collectDescendants(n.id);
    }
  }

  Set<String> _collectDescendants(String nodeId) {
    final out = <String>{nodeId};
    final stack = <String>[nodeId];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      final kids = _childrenByParent[cur] ?? const <IndexNode>[];
      for (final k in kids) {
        if (out.add(k.id)) stack.add(k.id);
      }
    }
    return out;
  }

  _TriState _stateOf(IndexNode n) {
    final desc = _descendantsByNode[n.id] ?? {n.id};
    // ¿Hojas dentro de los descendientes? Si lo evaluáramos solo por nodos
    // marcados, un Título con todos sus Capítulos marcados pero el propio
    // Título sin marcar daría "partial". Mejor evaluar por hojas:
    final leaves = <String>{};
    for (final id in desc) {
      final kids = _childrenByParent[id];
      if (kids == null || kids.isEmpty) leaves.add(id);
    }
    if (leaves.isEmpty) {
      // El propio nodo es hoja.
      return _selected.contains(n.id) ? _TriState.all : _TriState.none;
    }
    final marked = leaves.where(_selected.contains).length;
    if (marked == 0) return _TriState.none;
    if (marked == leaves.length) return _TriState.all;
    return _TriState.partial;
  }

  /// Marca/desmarca el nodo + todos sus descendientes y notifica al padre.
  void _toggle(IndexNode n, {required bool? value}) {
    final desc = _descendantsByNode[n.id] ?? {n.id};
    setState(() {
      if (value ?? false) {
        _selected.addAll(desc);
      } else {
        _selected.removeAll(desc);
      }
    });
    widget.onSelectionChanged({..._selected});
  }

  @override
  Widget build(BuildContext context) {
    // Nivel raiz del arbol: hijos directos del nodo sin parent (la raiz).
    final roots = _rootChildren();
    if (roots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          context.l10n.studyPickSectionTooltip,
          style: context.textTheme.bodySmall,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final root in roots) _rootEntry(root),
      ],
    );
  }

  List<IndexNode> _rootChildren() {
    // Buscar el id del nodo raiz: parentId == null. Puede haber mas de uno
    // por seguridad — usamos todos los nodos depth=0 como raices.
    final out = <IndexNode>[];
    for (final entry in _childrenByParent.entries) {
      final parentId = entry.key;
      if (parentId == null) {
        // hijos del null = el propio nodo raiz del subject; saltamos.
        continue;
      }
      // ¿Es hijo del nodo raiz?
      // Mejor: buscar nodos cuyo parent es la raiz del subject.
    }
    // Aproximacion mas simple: tomar todos los nodos depth=1 (hijos directos
    // del subject root).
    for (final n in widget.nodes) {
      if (n.depth == 1) out.add(n);
    }
    out.sort((a, b) => a.position.compareTo(b.position));
    return out;
  }

  /// Una entrada de nivel raíz (Título / Disposición). Usa estado propio para
  /// la animación de expand/collapse, pero el "uno solo a la vez" se decide
  /// comparando con [_expandedRootId].
  Widget _rootEntry(IndexNode root) {
    final state = _stateOf(root);
    final isExpanded = _expandedRootId == root.id;
    final hasChildren =
        (_childrenByParent[root.id] ?? const <IndexNode>[]).isNotEmpty;
    return _NodeRow(
      node: root,
      state: state,
      onToggle: (v) => _toggle(root, value: v),
      onExpand: hasChildren
          ? () {
              setState(() {
                _expandedRootId = isExpanded ? null : root.id;
              });
            }
          : null,
      isExpanded: isExpanded,
      // Indentación 0 al nivel raíz.
      depthIndent: 0,
      // Si está expandido, mostrar todos los descendientes con jerarquía.
      child: isExpanded
          ? _SubTree(
              node: root,
              childrenByParent: _childrenByParent,
              stateOf: _stateOf,
              onToggle: _toggle,
            )
          : null,
    );
  }
}

/// Sub-árbol recursivo: muestra todos los descendientes de un nodo padre,
/// indentados según su depth relativa.
class _SubTree extends StatefulWidget {
  const _SubTree({
    required this.node,
    required this.childrenByParent,
    required this.stateOf,
    required this.onToggle,
  });

  final IndexNode node;
  final Map<String?, List<IndexNode>> childrenByParent;
  final _TriState Function(IndexNode) stateOf;
  final void Function(IndexNode node, {required bool? value}) onToggle;

  @override
  State<_SubTree> createState() => _SubTreeState();
}

class _SubTreeState extends State<_SubTree> {
  final Set<String> _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final kids = widget.childrenByParent[widget.node.id] ?? const <IndexNode>[];
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final k in kids) _entry(k),
        ],
      ),
    );
  }

  Widget _entry(IndexNode n) {
    final state = widget.stateOf(n);
    final kids = widget.childrenByParent[n.id] ?? const <IndexNode>[];
    final hasKids = kids.isNotEmpty;
    final isExpanded = _expanded.contains(n.id);
    return _NodeRow(
      node: n,
      state: state,
      onToggle: (v) => widget.onToggle(n, value: v),
      onExpand: hasKids
          ? () => setState(() {
                if (isExpanded) {
                  _expanded.remove(n.id);
                } else {
                  _expanded.add(n.id);
                }
              })
          : null,
      isExpanded: isExpanded,
      depthIndent: (n.depth - 1).clamp(0, 4),
      child: isExpanded
          ? _SubTree(
              node: n,
              childrenByParent: widget.childrenByParent,
              stateOf: widget.stateOf,
              onToggle: widget.onToggle,
            )
          : null,
    );
  }
}

/// Una fila visual: chevron de expandir + checkbox tri-state + título + hijos.
class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.state,
    required this.onToggle,
    required this.onExpand,
    required this.isExpanded,
    required this.depthIndent,
    required this.child,
  });

  final IndexNode node;
  final _TriState state;
  final ValueChanged<bool?> onToggle;
  final VoidCallback? onExpand;
  final bool isExpanded;
  final int depthIndent;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final tri = switch (state) {
      _TriState.all => true,
      _TriState.none => false,
      _TriState.partial => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onExpand,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              4.0 + depthIndent * 12.0,
              2,
              4,
              2,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: onExpand == null
                      ? const SizedBox.shrink()
                      : Icon(
                          isExpanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                ),
                Checkbox(
                  value: tri,
                  tristate: true,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) {
                    // Al venir de null (parcial) o false -> marcar todo.
                    // Al venir de true -> desmarcar todo.
                    final next = state != _TriState.all;
                    onToggle(next);
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      fontWeight: depthIndent == 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}
