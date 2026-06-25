// ============================================================================
// subjects · IndexLeafPicker
// ----------------------------------------------------------------------------
// Variante del [IndexTreePicker] pensada para los configuradores de Test,
// V/F y Ensayo: el usuario solo puede elegir UNA seccion del indice y solo
// si esa seccion es HOJA (no tiene subsecciones). Los padres (Titulo,
// Capitulo, Seccion) son navegables (expandir/colapsar) pero NO selecciona-
// bles — la idea es forzar al usuario a estudiar punto por punto.
//
// Caracteristicas:
//   - Arbol acordeon, solo un padre del nivel raiz expandido a la vez (igual
//     que IndexTreePicker).
//   - Niveles intermedios expandibles libremente.
//   - Padres muestran chevron de expandir + titulo. SIN radio.
//   - Hojas muestran Radio + titulo. Solo una hoja puede estar marcada.
//   - Si el usuario tap en el padre, expande/colapsa (no selecciona).
//   - Notifica `onChanged(String? nodeId)` con el id de la hoja elegida.
// ============================================================================

import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';

import '../../../domain/subject.dart';

class IndexLeafPicker extends StatefulWidget {
  const IndexLeafPicker({
    required this.nodes,
    required this.selectedNodeId,
    required this.onChanged,
    super.key,
  });

  /// TODOS los nodos del subject (incluida la raiz). El widget filtra:
  /// la raiz no se muestra; sus hijos directos (Titulos / Disposiciones) son
  /// el nivel raiz del arbol; las hojas (sin hijos) son los elementos
  /// seleccionables.
  final List<IndexNode> nodes;

  /// Id de la hoja actualmente seleccionada, o `null` si no hay seleccion.
  final String? selectedNodeId;

  /// Notificado cuando el usuario elige (o deselecciona) una hoja. El
  /// argumento es el id de la hoja, o `null` si se deselecciono (raro,
  /// el Radio no produce null nativamente — lo mantenemos por simetria).
  final ValueChanged<String?> onChanged;

  @override
  State<IndexLeafPicker> createState() => _IndexLeafPickerState();
}

class _IndexLeafPickerState extends State<IndexLeafPicker> {
  /// Hijos directos de cada nodo (id -> List<IndexNode>).
  late Map<String?, List<IndexNode>> _childrenByParent;

  /// Id del padre raiz actualmente expandido (accordeon). `null` = ninguno.
  String? _expandedRootId;

  @override
  void initState() {
    super.initState();
    _buildIndex();
    // Si la seleccion inicial vive dentro de un padre raiz, lo expandimos
    // para que el usuario vea su propia eleccion al abrir el widget.
    _expandedRootId = _rootAncestorOf(widget.selectedNodeId);
  }

  @override
  void didUpdateWidget(covariant IndexLeafPicker old) {
    super.didUpdateWidget(old);
    if (old.nodes != widget.nodes) {
      _buildIndex();
    }
    if (old.selectedNodeId != widget.selectedNodeId &&
        widget.selectedNodeId != null) {
      _expandedRootId =
          _rootAncestorOf(widget.selectedNodeId) ?? _expandedRootId;
    }
  }

  void _buildIndex() {
    _childrenByParent = <String?, List<IndexNode>>{};
    for (final n in widget.nodes) {
      _childrenByParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    for (final list in _childrenByParent.values) {
      list.sort((a, b) {
        final byDepth = a.depth.compareTo(b.depth);
        if (byDepth != 0) return byDepth;
        return a.position.compareTo(b.position);
      });
    }
  }

  /// Sube por parentId hasta encontrar el ancestro de depth=1 (hijo directo
  /// de la raiz). Devuelve null si [nodeId] es null o no pertenece al subject.
  String? _rootAncestorOf(String? nodeId) {
    if (nodeId == null) return null;
    final byId = {for (final n in widget.nodes) n.id: n};
    var cur = byId[nodeId];
    while (cur != null && cur.depth > 1) {
      cur = byId[cur.parentId];
    }
    return cur?.id;
  }

  bool _isLeaf(IndexNode n) =>
      (_childrenByParent[n.id] ?? const <IndexNode>[]).isEmpty;

  @override
  Widget build(BuildContext context) {
    final roots = widget.nodes.where((n) => n.depth == 1).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
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
        for (final root in roots) _entry(root, depthIndent: 0),
      ],
    );
  }

  Widget _entry(IndexNode n, {required int depthIndent}) {
    final isLeaf = _isLeaf(n);
    final hasChildren = !isLeaf;
    final isRootLevel = n.depth == 1;
    final isExpanded = isRootLevel
        ? _expandedRootId == n.id
        : (_perEntryExpanded[n.id] ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            if (isLeaf) {
              widget.onChanged(n.id);
            } else {
              setState(() {
                if (isRootLevel) {
                  _expandedRootId = isExpanded ? null : n.id;
                } else {
                  if (isExpanded) {
                    _perEntryExpanded.remove(n.id);
                  } else {
                    _perEntryExpanded[n.id] = true;
                  }
                }
              });
            }
          },
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
                  child: hasChildren
                      ? Icon(
                          isExpanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 20,
                          color: context.colors.onSurfaceVariant,
                        )
                      : const SizedBox.shrink(),
                ),
                if (isLeaf)
                  Icon(
                    widget.selectedNodeId == n.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: widget.selectedNodeId == n.id
                        ? context.colors.primary
                        : context.colors.onSurfaceVariant,
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      fontWeight: isRootLevel
                          ? FontWeight.w700
                          : (hasChildren ? FontWeight.w500 : FontWeight.w400),
                      color: hasChildren
                          ? null
                          : (widget.selectedNodeId == n.id
                              ? context.colors.primary
                              : null),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasChildren && isExpanded) _expandedChildren(n, depthIndent),
      ],
    );
  }

  /// Renderiza los hijos de un nodo expandido. Si son muchos (>50) los
  /// envuelve en un area scrollable con altura limitada para que no se
  /// coma la pantalla cuando un Titulo tiene 30 articulos planos.
  Widget _expandedChildren(IndexNode parent, int depthIndent) {
    final kids = _childrenByParent[parent.id] ?? const <IndexNode>[];
    final entries = [
      for (final c in kids) _entry(c, depthIndent: depthIndent + 1),
    ];
    if (kids.length <= 50) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: entries,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 480),
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: entries,
        ),
      ),
    );
  }

  /// Estado expand/collapse para padres NO root (capitulos, secciones, etc.).
  /// Estos no estan sujetos al accordeon de nivel raiz.
  final Map<String, bool> _perEntryExpanded = <String, bool>{};
}
