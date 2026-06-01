// ============================================================================
// subjects · Workspace de estudio (Fase 2) — layout tipo NotebookLM
// ----------------------------------------------------------------------------
// Tres columnas redimensionables para un temario:
//   - IZQUIERDA: el ÍNDICE (con sus fuentes/documentos arriba). Permite subir
//     material, generar el índice, validarlo (bloquea regeneración) y navegar
//     por las secciones.
//   - CENTRO: el contenido de la sección seleccionada en pestañas
//     (Original / Explicado / Resumen) y, abajo, una barra para preguntar a la
//     IA (próximamente).
//   - DERECHA: "Estudio" — Notas (operativas) + Flashcards / Cuestionario /
//     Mapa mental (próximamente).
// El ancho de cada columna se puede ajustar arrastrando los separadores y se
// recuerda entre sesiones (SharedPreferences).
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/markdown_text.dart';
import 'package:myapp/core/widgets/premium/premium.dart';
import 'package:myapp/core/widgets/readable_text.dart';
import 'package:myapp/core/widgets/reader_frame.dart';

import '../../application/subjects_providers.dart';
import '../../data/subjects_datasource.dart';
import '../../domain/subject.dart';
import '../util/file_picker_web.dart';
import '../util/study_export.dart';
import '../util/study_tts.dart';
import '../widgets/collapsible_index_tree.dart';
import '../widgets/runners/mind_map_view.dart';
import '../widgets/runners/mock_exam_view.dart';
import '../widgets/runners/show_test_modal.dart';
import '../widgets/runners/test_runner_dialog.dart';
import '../widgets/runners/tf_view.dart';

const double _kMinColWidth = 240;
const double _kHandleWidth = 36;
const double _kStackedBreakpoint = 1000;
const String _kPrefLeftFrac = 'study_left_frac';
const String _kPrefRightFrac = 'study_right_frac';

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
  // Temario para el que ya hemos mostrado el modal de revisión del índice en
  // esta sesión (evita reabrirlo en cada rebuild del polling).
  String? _reviewPromptedFor;
  bool _reviewing = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPolling(bool active) {
    if (active) {
      _poll ??= Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) {
          _poll?.cancel();
          _poll = null;
          return;
        }
        ref
          ..invalidate(subjectsListProvider)
          ..invalidate(subjectDocumentsProvider(widget.subject.id));
      });
    } else if (_poll != null) {
      _poll!.cancel();
      _poll = null;
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
        SnackBar(backgroundColor: errBg, content: Text(l.studyIndexFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

  /// Modal de revisión del índice recién generado: lo muestra y pide aceptarlo
  /// (validar = bloquear, ya no se puede regenerar) o regenerarlo.
  Future<void> _promptIndexReview(List<IndexNode> ordered) async {
    if (_reviewing) return;
    _reviewing = true;
    final l = context.l10n;
    final scheme = context.colors;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    final h = (MediaQuery.sizeOf(context).height - 200).clamp(360.0, 900.0);
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      // Fondo OPACO: mientras se revisa, solo se ve este modal (lo demás no).
      barrierColor: scheme.surface,
      builder: (ctx) => AlertDialog(
        title: Text(l.studySetupReview),
        content: SizedBox(
          width: 480,
          height: h,
          child: CollapsibleIndexTree(nodes: ordered),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'regen'),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(l.studySetupRegenerate),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'accept'),
            icon: const Icon(Icons.check, size: 16),
            label: Text(l.studyValidateIndex),
          ),
        ],
      ),
    );
    _reviewing = false;
    if (!mounted) return;
    if (action == 'accept') {
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
      }
    } else if (action == 'regen') {
      // Permitir que vuelva a saltar el modal cuando esté listo de nuevo.
      _reviewPromptedFor = null;
      await _generateIndex();
    }
  }

  /// Recorrido DFS para indentar el árbol del índice.
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

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(subjectDocumentsProvider(widget.subject.id));
    final anyDocInProgress =
        docsAsync.valueOrNull?.any((d) => d.inProgress) ?? false;
    _syncPolling(widget.subject.indexGenerating || anyDocInProgress);

    final nodesAsync = ref.watch(indexNodesProvider(widget.subject.id));
    final nodes = nodesAsync.valueOrNull ?? const <IndexNode>[];
    final ordered = _dfs(nodes);
    final selectedId = ordered.any((n) => n.id == _selectedNodeId)
        ? _selectedNodeId
        : (ordered.isNotEmpty ? ordered.first.id : null);

    // Índice LISTO pero SIN VALIDAR → modal de revisión (aceptar = bloquear /
    // regenerar) antes de dejar trabajar. Una sola vez por temario y sesión.
    if (widget.subject.indexReady &&
        !widget.subject.indexLocked &&
        ordered.isNotEmpty &&
        !_busy &&
        _reviewPromptedFor != widget.subject.id) {
      _reviewPromptedFor = widget.subject.id;
      final toReview = ordered;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _promptIndexReview(toReview);
      });
    }

    final left = _IndexColumn(
      subject: widget.subject,
      orderedNodes: ordered,
      nodesLoading: nodesAsync.isLoading,
      selectedId: selectedId,
      aiNodeIds: ref
              .watch(aiContentNodeIdsProvider(widget.subject.id))
              .valueOrNull ??
          const <String>{},
      busy: _busy,
      onSelect: (id) => setState(() => _selectedNodeId = id),
      onGenerate: _generateIndex,
      onValidate: _validateIndex,
    );
    final center = _ContentColumn(
      subjectId: widget.subject.id,
      nodeId: selectedId,
      nodeTitle: ordered
          .where((n) => n.id == selectedId)
          .map((n) => n.title)
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null),
      nodes: ordered,
      onSelectNode: (id) => setState(() => _selectedNodeId = id),
    );
    final right = _StudioColumn(
      subjectId: widget.subject.id,
      nodeId: selectedId,
      onSelectNode: (id) => setState(() => _selectedNodeId = id),
      examDate: widget.subject.examDate,
      sectionCount: ordered.where((n) => n.parentId != null).length,
      nodes: ordered,
    );

    return LayoutBuilder(
      builder: (ctx, c) {
        if (c.maxWidth < _kStackedBreakpoint) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            children: [
              SizedBox(height: 420, child: left),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(height: 520, child: center),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(height: 460, child: right),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: _ResizableRow(left: left, center: center, right: right),
        );
      },
    );
  }
}

// ─────────────────────────── Columnas redimensionables ──────────────────────

/// Fila de 3 columnas con separadores arrastrables; recuerda los anchos.
class _ResizableRow extends ConsumerStatefulWidget {
  const _ResizableRow({
    required this.left,
    required this.center,
    required this.right,
  });

  final Widget left;
  final Widget center;
  final Widget right;

  @override
  ConsumerState<_ResizableRow> createState() => _ResizableRowState();
}

class _ResizableRowState extends ConsumerState<_ResizableRow> {
  double _leftF = 0.24;
  double _rightF = 0.28;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    _leftF = prefs.getDouble(_kPrefLeftFrac) ?? 0.24;
    _rightF = prefs.getDouble(_kPrefRightFrac) ?? 0.28;
  }

  void _persist() {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs
      ..setDouble(_kPrefLeftFrac, _leftF)
      ..setDouble(_kPrefRightFrac, _rightF);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final avail = c.maxWidth - 2 * _kHandleWidth;
        if (avail <= 3 * _kMinColWidth) {
          // Demasiado estrecho para 3 columnas con mínimos: reparto a tercios.
          final w = avail / 3;
          return Row(
            children: [
              SizedBox(width: w, child: widget.left),
              const SizedBox(width: _kHandleWidth),
              SizedBox(width: w, child: widget.center),
              const SizedBox(width: _kHandleWidth),
              SizedBox(width: w, child: widget.right),
            ],
          );
        }
        final maxSide = avail - 2 * _kMinColWidth;
        var leftW = (_leftF * avail).clamp(_kMinColWidth, maxSide);
        var rightW = (_rightF * avail).clamp(_kMinColWidth, avail - leftW - _kMinColWidth);
        final centerW = avail - leftW - rightW;

        return Row(
          children: [
            SizedBox(width: leftW, child: widget.left),
            _DragHandle(
              onDelta: (dx) {
                setState(() {
                  leftW = (leftW + dx)
                      .clamp(_kMinColWidth, avail - rightW - _kMinColWidth);
                  _leftF = leftW / avail;
                });
              },
              onEnd: _persist,
            ),
            SizedBox(width: centerW, child: widget.center),
            _DragHandle(
              onDelta: (dx) {
                setState(() {
                  rightW = (rightW - dx)
                      .clamp(_kMinColWidth, avail - leftW - _kMinColWidth);
                  _rightF = rightW / avail;
                });
              },
              onEnd: _persist,
            ),
            SizedBox(width: rightW, child: widget.right),
          ],
        );
      },
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onDelta, required this.onEnd});

  final ValueChanged<double> onDelta;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        child: SizedBox(
          width: _kHandleWidth,
          child: Center(
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: context.colors.outlineVariant,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marco común de columna: card con cabecera (título + acciones) y cuerpo.
class _ColumnCard extends StatelessWidget {
  const _ColumnCard({
    required this.title,
    required this.body,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final IconData? leading;
  final List<Widget> actions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  Icon(leading, size: 18, color: context.colors.primary),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

// ─────────────────────────────── Columna ÍNDICE ─────────────────────────────

class _IndexColumn extends ConsumerWidget {
  const _IndexColumn({
    required this.subject,
    required this.orderedNodes,
    required this.nodesLoading,
    required this.selectedId,
    required this.aiNodeIds,
    required this.busy,
    required this.onSelect,
    required this.onGenerate,
    required this.onValidate,
  });

  final Subject subject;
  final List<IndexNode> orderedNodes;
  final bool nodesLoading;
  final String? selectedId;
  final Set<String> aiNodeIds;
  final bool busy;
  final ValueChanged<String> onSelect;
  final VoidCallback onGenerate;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final locked = subject.indexLocked;
    final ready = subject.indexReady && orderedNodes.isNotEmpty;

    final actions = <Widget>[
      if (ready)
        if (locked)
          Tooltip(
            message: l.studyIndexValidated,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.verified_outlined,
                size: 18,
                color: context.colors.primary,
              ),
            ),
          )
        else ...[
          IconButton(
            tooltip: l.studyValidateIndex,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.verified_outlined, size: 18),
            onPressed: busy ? null : onValidate,
          ),
          IconButton(
            tooltip: l.studyRegenerate,
            visualDensity: VisualDensity.compact,
            icon: busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh, size: 18),
            onPressed: busy ? null : onGenerate,
          ),
        ],
    ];

    return _ColumnCard(
      title: l.studyIndexTitle,
      leading: Icons.account_tree_outlined,
      actions: actions,
      body: _indexBody(context, ref),
    );
  }

  Widget _indexBody(BuildContext context, WidgetRef ref) {
    final l = context.l10n;

    if (subject.indexGenerating) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.studyIndexGenerating, style: context.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(6)),
              child: LinearProgressIndicator(minHeight: 4),
            ),
          ],
        ),
      );
    }

    if (!subject.indexReady || orderedNodes.isEmpty) {
      final docsAsync = ref.watch(subjectDocumentsProvider(subject.id));
      final hasReady =
          docsAsync.valueOrNull?.any((d) => d.status == DocStatus.ready) ??
              false;
      final failed = subject.indexStatus == IndexStatus.failed;
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              failed
                  ? l.studyIndexFailed
                  : (hasReady ? l.studyIndexTitle : l.studyIndexNeedsDoc),
              style: context.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            PremiumButton(
              label: l.studyGenerateIndex,
              leadingIcon: Icons.auto_awesome_outlined,
              loading: busy,
              onPressed: (busy || !hasReady || subject.indexLocked)
                  ? null
                  : onGenerate,
            ),
          ],
        ),
      );
    }

    return _IndexTree(
      nodes: orderedNodes,
      selectedId: selectedId,
      aiNodeIds: aiNodeIds,
      onSelect: onSelect,
    );
  }
}

/// Árbol del índice (solo las filas, en acordeón). La cabecera/acciones las pone
/// la columna contenedora.
class _IndexTree extends StatefulWidget {
  const _IndexTree({
    required this.nodes,
    required this.selectedId,
    required this.aiNodeIds,
    required this.onSelect,
  });

  final List<IndexNode> nodes;
  final String? selectedId;
  final Set<String> aiNodeIds;
  final ValueChanged<String> onSelect;

  @override
  State<_IndexTree> createState() => _IndexTreeState();
}

class _IndexTreeState extends State<_IndexTree> {
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

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      children: rows,
    );
  }
}

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
  final bool hasAi;
  final bool expanded;
  final bool selected;
  final VoidCallback? onToggle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return InkWell(
      onTap: () {
        onSelect();
        // Pulsar el título también despliega la carpeta (no la colapsa: para
        // cerrarla se usa el icono de la izquierda).
        if (hasChildren && !expanded) onToggle?.call();
      },
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
              Icon(
                hasChildren ? Icons.folder_rounded : Icons.fiber_manual_record,
                size: hasChildren ? 17 : 10,
                color: hasChildren ? Colors.amber.shade700 : scheme.onSurface,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    // Las carpetas (con subapartados) siempre en negrita.
                    fontWeight: hasChildren
                        ? FontWeight.w800
                        : (selected ? FontWeight.w700 : FontWeight.w500),
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

// ─────────────────────────────── Columna CENTRO ─────────────────────────────

class _ContentColumn extends ConsumerStatefulWidget {
  const _ContentColumn({
    required this.subjectId,
    required this.nodeId,
    required this.nodeTitle,
    required this.nodes,
    required this.onSelectNode,
  });

  final String subjectId;
  final String? nodeId;
  final String? nodeTitle;
  final List<IndexNode> nodes;
  final ValueChanged<String> onSelectNode;

  @override
  ConsumerState<_ContentColumn> createState() => _ContentColumnState();
}

class _ContentColumnState extends ConsumerState<_ContentColumn> {
  /// Chat acoplado a la card: oculto por defecto. Se abre con el botón flotante
  /// abajo a la derecha; el botón de cerrar lo oculta y vuelve al contenido.
  bool _chatOpen = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final nodeId = widget.nodeId;
    if (nodeId == null) {
      return _ColumnCard(
        title: l.studyTabOriginal,
        leading: Icons.menu_book_outlined,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              l.studySelectNode,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    // Contenido normal (raíz / carpeta / hoja). Siempre presente debajo, así
    // sigue visible/clicable cuando el chat se abre desde abajo.
    IndexNode? selected;
    for (final n in widget.nodes) {
      if (n.id == nodeId) {
        selected = n;
        break;
      }
    }

    final Widget body;
    if (selected != null && selected.parentId == null) {
      body = _RootOriginalView(
        subjectId: widget.subjectId,
        title: widget.nodeTitle ?? '',
      );
    } else if (widget.nodes.any((n) => n.parentId == nodeId)) {
      body = _folderBody(context, nodeId);
    } else {
      body = _tabbed(context, nodeId);
    }

    // Panel de chat deslizante (bottom sheet acoplado a la card): sube desde
    // abajo cubriendo ~55% del card (con techo en 440 px y suelo en 260) y deja
    // siempre visible el contenido detrás, con un velo semitransparente para
    // que se perciba claramente que está SUPERPUESTO. El botón flotante se
    // desvanece mientras el chat está abierto. La IA solo responde sobre este
    // temario o la sección activa (lo fuerza el system prompt de `ask-subject`).
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // Si el padre no acota la altura (caso defensivo), usamos un valor fijo
        // razonable para que el sheet no degenere a pantalla completa.
        final hasBounded = constraints.maxHeight.isFinite;
        final base = hasBounded ? constraints.maxHeight : 560.0;
        final panelHeight = (base * 0.55).clamp(260.0, 440.0);
        final scheme = Theme.of(context).colorScheme;
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: body),
              // Velo: fade-in cuando se abre el chat, transparente cuando se
              // cierra. Cliquear el velo cierra el panel.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_chatOpen,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _chatOpen ? 1 : 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _chatOpen = false),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _chatOpen ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: _chatOpen,
                    child: FloatingActionButton.small(
                      heroTag: 'study_chat_open',
                      tooltip: l.studyTabChat,
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      onPressed: () => setState(() => _chatOpen = true),
                      child: const Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: panelHeight,
                child: IgnorePointer(
                  ignoring: !_chatOpen,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    offset: _chatOpen ? Offset.zero : const Offset(0, 1.1),
                    child: _chatPanel(context),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _folderBody(BuildContext context, String nodeId) {
    final introAsync =
        ref.watch(nodeContentProvider((nodeId: nodeId, kind: 'intro')));
    return introAsync.when(
      loading: () => _ColumnCard(
        title: widget.nodeTitle ?? '',
        leading: Icons.folder_rounded,
        body: const Center(child: AppLoadingState()),
      ),
      error: (_, __) => _folderStructure(context, nodeId),
      data: (intro) {
        if (intro != null && intro.trim().isNotEmpty) {
          return _ColumnCard(
            title: widget.nodeTitle ?? '',
            leading: Icons.menu_book_outlined,
            body: ReaderFrame(child: MarkdownText(intro)),
          );
        }
        return _folderStructure(context, nodeId);
      },
    );
  }

  /// Card con la ESTRUCTURA de la carpeta (títulos de sus subíndices).
  Widget _folderStructure(BuildContext context, String nodeId) {
    return _ColumnCard(
      title: widget.nodeTitle ?? '',
      leading: Icons.folder_rounded,
      body: _FolderStructureView(
        folderId: nodeId,
        nodes: widget.nodes,
        onSelectNode: widget.onSelectNode,
      ),
    );
  }

  Widget _tabbed(BuildContext context, String nodeId) {
    final l = context.l10n;
    return PremiumCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: Text(
                widget.nodeTitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: l.studyTabOriginal),
                Tab(text: l.studyTabExplained),
                Tab(text: l.studyTabSummary),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _NodeView(
                    nodeId: nodeId,
                    kind: 'original',
                    subjectId: widget.subjectId,
                  ),
                  _NodeView(
                    nodeId: nodeId,
                    kind: 'explained',
                    subjectId: widget.subjectId,
                  ),
                  _NodeView(
                    nodeId: nodeId,
                    kind: 'summary',
                    subjectId: widget.subjectId,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hoja DESLIZANTE de chat: aparece por la parte inferior del card central,
  /// con cabecera (icono + título + cerrar) y el contenido de chat debajo. La
  /// IA solo responde sobre el temario o la sección activa.
  Widget _chatPanel(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 12,
      color: scheme.surface,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              border: Border(
                bottom: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.18),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l.studyTabChat,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: l.actionClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _chatOpen = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _ChatView(
              key: ValueKey('chat_${widget.subjectId}'),
              subjectId: widget.subjectId,
              nodeId: widget.nodeId,
              nodes: widget.nodes,
              onSelectNode: widget.onSelectNode,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vista del nodo RAÍZ (título del temario): muestra el DOCUMENTO COMPLETO tal
/// cual su contenido (texto extraído), navegable por el índice (cada sección
/// muestra su parte). Botón "Ver original" para abrir el archivo subido tal cual.
class _RootOriginalView extends ConsumerStatefulWidget {
  const _RootOriginalView({required this.subjectId, required this.title});

  final String subjectId;
  final String title;

  @override
  ConsumerState<_RootOriginalView> createState() => _RootOriginalViewState();
}

class _RootOriginalViewState extends ConsumerState<_RootOriginalView> {
  bool _busy = false;

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
    final async = ref.watch(subjectFullTextProvider(widget.subjectId));
    return _ColumnCard(
      title: widget.title,
      leading: Icons.menu_book_outlined,
      actions: [
        IconButton(
          tooltip: l.studyOpenOriginal,
          visualDensity: VisualDensity.compact,
          icon: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.open_in_new, size: 18),
          onPressed: _busy ? null : _openOriginal,
        ),
      ],
      body: async.when(
        loading: () => const Center(child: AppLoadingState()),
        error: (e, _) => AppErrorState(
          message: l.studyViewError,
          detail: e.toString(),
          onRetry: () =>
              ref.invalidate(subjectFullTextProvider(widget.subjectId)),
          retryLabel: l.actionRetry,
        ),
        data: (text) {
          if (text == null || text.trim().isEmpty) {
            // Sin texto extraído: ofrecemos abrir el archivo original tal cual.
            return Center(
              child: PremiumButton(
                label: l.studyOpenOriginal,
                leadingIcon: Icons.open_in_new,
                loading: _busy,
                onPressed: _busy ? null : _openOriginal,
              ),
            );
          }
          return ReaderFrame(child: ReadableText(text));
        },
      ),
    );
  }
}

/// Vista de la ESTRUCTURA de una carpeta del índice: lista (indentada y
/// clicable) de sus subapartados, para usar cuando la carpeta no tiene
/// contenido propio. Pulsar un elemento navega a esa sección.
class _FolderStructureView extends StatelessWidget {
  const _FolderStructureView({
    required this.folderId,
    required this.nodes,
    required this.onSelectNode,
  });

  final String folderId;
  final List<IndexNode> nodes;
  final ValueChanged<String> onSelectNode;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final byParent = <String?, List<IndexNode>>{};
    for (final n in nodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.position.compareTo(b.position));
    }
    var baseDepth = 0;
    for (final n in nodes) {
      if (n.id == folderId) {
        baseDepth = n.depth;
        break;
      }
    }

    final rows = <Widget>[];
    void emit(IndexNode n) {
      final children = byParent[n.id] ?? const <IndexNode>[];
      final isFolder = children.isNotEmpty;
      rows.add(
        InkWell(
          onTap: () => onSelectNode(n.id),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.sm + (n.depth - baseDepth - 1) * 16.0,
              8,
              AppSpacing.sm,
              8,
            ),
            child: Row(
              children: [
                Icon(
                  isFolder ? Icons.folder_rounded : Icons.fiber_manual_record,
                  size: isFolder ? 17 : 10,
                  color:
                      isFolder ? Colors.amber.shade700 : scheme.onSurface,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    n.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isFolder ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 16, color: scheme.onSurfaceVariant,),
              ],
            ),
          ),
        ),
      );
      for (final c in children) {
        emit(c);
      }
    }

    for (final c in byParent[folderId] ?? const <IndexNode>[]) {
      emit(c);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            l.studyFolderStructure,
            style: context.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        ...rows,
      ],
    );
  }
}

/// Mensaje de la conversación del chat.
typedef _ChatMsg = ({bool fromUser, String text});

/// Chat para preguntar a la IA sobre el temario / la sección seleccionada.
/// La conversación vive en memoria mientras dura la sesión del temario.
class _ChatView extends ConsumerStatefulWidget {
  const _ChatView({
    required this.subjectId,
    required this.nodeId,
    required this.nodes,
    required this.onSelectNode,
    super.key,
  });

  final String subjectId;
  final String? nodeId;
  final List<IndexNode> nodes;
  final ValueChanged<String> onSelectNode;

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMsg> _messages = [];
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final msgs = await ref
          .read(subjectsDataSourceProvider)
          .listChatMessages(widget.subjectId);
      if (mounted) {
        setState(() {
          _messages
            ..clear()
            ..addAll(msgs);
          _loading = false;
        });
        _scrollToEnd();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    if (_busy || _messages.isEmpty) return;
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.studyChatClearTitle,
      body: l.studyChatClearBody,
      confirmLabel: l.studyNoteDelete,
      danger: true,
    );
    if (ok != true || !mounted) return;
    setState(_messages.clear);
    try {
      await ref
          .read(subjectsDataSourceProvider)
          .clearChatMessages(widget.subjectId);
    } catch (_) {
      // best-effort
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _busy) return;
    final l = context.l10n;
    // Historial (antes de añadir el nuevo turno).
    final history = [
      for (final m in _messages)
        {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
    ];
    setState(() {
      _messages.add((fromUser: true, text: q));
      _busy = true;
      _ctrl.clear();
    });
    _scrollToEnd();
    final ds = ref.read(subjectsDataSourceProvider);
    try {
      // Persistimos la pregunta antes de llamar a la IA (así se guarda aunque
      // la respuesta falle).
      await ds.addChatMessage(
        subjectId: widget.subjectId,
        fromUser: true,
        content: q,
      );
      final answer = await ds.askSubject(
        subjectId: widget.subjectId,
        nodeId: widget.nodeId,
        question: q,
        history: history,
      );
      if (mounted) {
        setState(() => _messages.add((fromUser: false, text: answer)));
      }
      await ds.addChatMessage(
        subjectId: widget.subjectId,
        fromUser: false,
        content: answer,
      );
    } on SubjectsException catch (e) {
      final detail =
          e.detail != null && e.detail!.isNotEmpty ? ' (${e.detail})' : '';
      if (mounted) {
        setState(() => _messages.add(
              (fromUser: false, text: '⚠️ ${l.studyViewError}$detail'),
            ),);
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _messages.add((fromUser: false, text: '⚠️ ${l.studyViewError}')),);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_loading) return const Center(child: AppLoadingState());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_messages.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : _clear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: Text(l.studyChatClear),
            ),
          ),
        Expanded(
          child: _messages.isEmpty && !_busy
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      l.studyChatEmpty,
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  itemCount: _messages.length + (_busy ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i >= _messages.length) {
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Row(
                          children: [
                            const SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              l.studyGenerating,
                              style: context.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    }
                    return _bubble(context, _messages[i]);
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: l.studyAskHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton.filled(
                tooltip: l.studyChatSend,
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Extrae las secciones citadas como [[Título]] y las casa con los nodos del
  /// índice (igualdad o "contiene", sin distinguir mayúsculas). Únicas por id.
  List<IndexNode> _citations(String text) {
    final out = <IndexNode>[];
    final seen = <String>{};
    for (final mch in RegExp(r'\[\[(.+?)\]\]').allMatches(text)) {
      final cap = mch.group(1)!.trim().toLowerCase();
      if (cap.isEmpty) continue;
      for (final n in widget.nodes) {
        final t = n.title.trim().toLowerCase();
        if (t.isEmpty) continue;
        if ((t == cap || t.contains(cap) || cap.contains(t)) &&
            seen.add(n.id)) {
          out.add(n);
          break;
        }
      }
    }
    return out;
  }

  Widget _bubble(BuildContext context, _ChatMsg m) {
    final scheme = context.colors;
    final l = context.l10n;
    // En las respuestas de la IA, convertimos [[Título]] en texto normal y
    // añadimos chips clicables debajo que saltan a la sección citada.
    final citations = m.fromUser ? const <IndexNode>[] : _citations(m.text);
    final clean = m.fromUser
        ? m.text
        : m.text.replaceAllMapped(
            RegExp(r'\[\[(.+?)\]\]'),
            (mch) => mch.group(1) ?? '',
          );
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: m.fromUser
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.fromUser)
              Text(clean, style: context.textTheme.bodyMedium)
            else
              MarkdownText(clean),
            if (citations.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                l.studyChatSources,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in citations)
                    ActionChip(
                      avatar: const Icon(Icons.link, size: 14),
                      label: Text(
                        n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => widget.onSelectNode(n.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Una pestaña de contenido: muestra la vista cacheada o un botón para generarla.
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
  bool _speaking = false;

  NodeViewKey get _key => (nodeId: widget.nodeId, kind: widget.kind);

  @override
  void dispose() {
    if (_speaking) ttsStop();
    super.dispose();
  }

  void _toggleSpeak(String content) {
    if (_speaking) {
      ttsStop();
      setState(() => _speaking = false);
    } else {
      ttsSpeak(content, lang: Localizations.localeOf(context).toLanguageTag());
      setState(() => _speaking = true);
    }
  }

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
      ref
        ..invalidate(
          nodeContentProvider((nodeId: widget.nodeId, kind: 'explained')),
        )
        ..invalidate(
          nodeContentProvider((nodeId: widget.nodeId, kind: 'summary')),
        )
        ..invalidate(aiContentNodeIdsProvider(widget.subjectId));
    } on SubjectsException catch (e) {
      final detail =
          e.detail != null && e.detail!.isNotEmpty ? ': ${e.detail}' : '';
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          duration: const Duration(seconds: 8),
          content: Text('${l.studyViewError} (${e.code})$detail'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.studyViewError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

        if (isOriginal) {
          if (hasContent) return _scroll(context, content, markdown: false);
          return Center(
            child: PremiumButton(
              label: l.studyOpenOriginal,
              leadingIcon: Icons.open_in_new,
              loading: _busy,
              onPressed: _busy ? null : _openOriginal,
            ),
          );
        }

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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: _speaking ? l.studyTtsStop : l.studyTtsListen,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _speaking
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_outlined,
                    size: 18,
                  ),
                  onPressed: () => _toggleSpeak(content),
                ),
                IconButton(
                  tooltip: l.studyExport,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  onPressed: () => downloadStudyText(
                    filename: '${widget.kind}.md',
                    text: content,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _generate(force: true),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l.studyRegenerate),
                ),
              ],
            ),
            Expanded(child: _scroll(context, content, markdown: true)),
          ],
        );
      },
    );
  }

  Widget _scroll(BuildContext context, String content, {required bool markdown}) {
    return ReaderFrame(
      // Vista verbatim (Original) -> ReadableText con párrafos y sangría.
      // Vistas IA (Explicado / Resumen) -> Markdown con su propia tipografía.
      child: markdown ? MarkdownText(content) : ReadableText(content),
    );
  }
}

// ─────────────────────────────── Columna ESTUDIO ────────────────────────────

enum _StudioTool {
  home,
  notes,
  flashcards,
  mindmap,
  quiz,
  guide,
  exam,
  mock,
  tf,
  essay,
  progress,
  history,
}

class _StudioColumn extends StatefulWidget {
  const _StudioColumn({
    required this.subjectId,
    required this.nodeId,
    required this.onSelectNode,
    required this.examDate,
    required this.sectionCount,
    required this.nodes,
  });

  final String subjectId;
  final String? nodeId;
  final ValueChanged<String> onSelectNode;
  final DateTime? examDate;
  final int sectionCount;
  final List<IndexNode> nodes;

  @override
  State<_StudioColumn> createState() => _StudioColumnState();
}

class _StudioColumnState extends State<_StudioColumn> {
  _StudioTool _tool = _StudioTool.home;

  /// Título de la sección actualmente activa (si la hay), para mostrarlo en
  /// los headers de las herramientas con ámbito de sección (Flashcards / Quiz).
  String? _activeNodeTitle() {
    final id = widget.nodeId;
    if (id == null) return null;
    for (final n in widget.nodes) {
      if (n.id == id) return n.title;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final inNotes = _tool == _StudioTool.notes && widget.nodeId != null;
    final inFlash = _tool == _StudioTool.flashcards;
    final inMind = _tool == _StudioTool.mindmap;
    final inQuiz = _tool == _StudioTool.quiz;
    final inGuide = _tool == _StudioTool.guide;
    final inExam = _tool == _StudioTool.exam;
    final inMock = _tool == _StudioTool.mock;
    final inTf = _tool == _StudioTool.tf;
    final inEssay = _tool == _StudioTool.essay;
    final inProgress = _tool == _StudioTool.progress;
    final inHistory = _tool == _StudioTool.history;

    final String title;
    final IconData leading;
    if (inNotes) {
      title = l.studyTabNotes;
      leading = Icons.sticky_note_2_outlined;
    } else if (inFlash) {
      title = l.studioFlashcards;
      leading = Icons.style_outlined;
    } else if (inMind) {
      title = l.studioMindmap;
      leading = Icons.hub_outlined;
    } else if (inQuiz) {
      title = l.studioQuiz;
      leading = Icons.quiz_outlined;
    } else if (inGuide) {
      title = l.studioGuide;
      leading = Icons.menu_book_outlined;
    } else if (inExam) {
      title = l.studyExamLabel;
      leading = Icons.event_outlined;
    } else if (inMock) {
      title = l.studioTest;
      leading = Icons.fact_check_outlined;
    } else if (inTf) {
      title = l.studioTf;
      leading = Icons.rule;
    } else if (inEssay) {
      title = l.studioEssay;
      leading = Icons.edit_note;
    } else if (inProgress) {
      title = l.studioProgress;
      leading = Icons.insights_outlined;
    } else if (inHistory) {
      title = l.studioHistory;
      leading = Icons.history;
    } else {
      title = l.studioTitle;
      leading = Icons.auto_awesome;
    }

    final Widget body;
    if (inNotes) {
      body = _NotesView(nodeId: widget.nodeId!, subjectId: widget.subjectId);
    } else if (inFlash) {
      body = _FlashcardsView(
        subjectId: widget.subjectId,
        activeNodeId: widget.nodeId,
        activeNodeTitle: _activeNodeTitle(),
      );
    } else if (inMind) {
      body = MindMapView(
        subjectId: widget.subjectId,
        selectedId: widget.nodeId,
        onSelectNode: widget.onSelectNode,
      );
    } else if (inQuiz) {
      body = _QuizView(
        subjectId: widget.subjectId,
        activeNodeId: widget.nodeId,
        activeNodeTitle: _activeNodeTitle(),
      );
    } else if (inGuide) {
      body = _GuideView(subjectId: widget.subjectId);
    } else if (inExam) {
      body = _ExamView(
        subjectId: widget.subjectId,
        examDate: widget.examDate,
        sectionCount: widget.sectionCount,
      );
    } else if (inMock) {
      body = MockExamView(
        subjectId: widget.subjectId,
        nodes: widget.nodes,
        onSelectNode: widget.onSelectNode,
      );
    } else if (inTf) {
      body = TfView(
        subjectId: widget.subjectId,
        nodes: widget.nodes,
      );
    } else if (inEssay) {
      body = _EssayView(
        subjectId: widget.subjectId,
        nodes: widget.nodes,
      );
    } else if (inProgress) {
      body = _ProgressView(subjectId: widget.subjectId);
    } else if (inHistory) {
      body = _HistoryView(
        subjectId: widget.subjectId,
        onSelectNode: widget.onSelectNode,
      );
    } else {
      body = _studioGrid(context);
    }

    return _ColumnCard(
      title: title,
      leading: leading,
      actions: [
        if (inNotes ||
            inFlash ||
            inMind ||
            inQuiz ||
            inGuide ||
            inExam ||
            inMock ||
            inTf ||
            inEssay ||
            inProgress ||
            inHistory)
          IconButton(
            tooltip: l.actionCancel,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_back, size: 18),
            onPressed: () => setState(() => _tool = _StudioTool.home),
          ),
      ],
      body: body,
    );
  }

  Widget _studioGrid(BuildContext context) {
    final l = context.l10n;
    final canNotes = widget.nodeId != null;
    final tiles = <Widget>[
      _StudioTile(
        icon: Icons.sticky_note_2_outlined,
        label: l.studyTabNotes,
        color: Colors.amber.shade700,
        enabled: canNotes,
        onTap: canNotes
            ? () => setState(() => _tool = _StudioTool.notes)
            : null,
      ),
      _StudioTile(
        icon: Icons.style_outlined,
        label: l.studioFlashcards,
        color: Colors.blue.shade600,
        onTap: () => setState(() => _tool = _StudioTool.flashcards),
      ),
      _StudioTile(
        icon: Icons.quiz_outlined,
        label: l.studioQuiz,
        color: Colors.deepPurple.shade400,
        onTap: () => setState(() => _tool = _StudioTool.quiz),
      ),
      _StudioTile(
        icon: Icons.hub_outlined,
        label: l.studioMindmap,
        color: Colors.teal.shade500,
        onTap: () => setState(() => _tool = _StudioTool.mindmap),
      ),
      _StudioTile(
        icon: Icons.menu_book_outlined,
        label: l.studioGuide,
        color: Colors.green.shade600,
        onTap: () => setState(() => _tool = _StudioTool.guide),
      ),
      _StudioTile(
        icon: Icons.event_outlined,
        label: l.studyExamLabel,
        color: Colors.deepOrange.shade400,
        onTap: () => setState(() => _tool = _StudioTool.exam),
      ),
      _StudioTile(
        icon: Icons.fact_check_outlined,
        label: l.studioTest,
        color: Colors.indigo.shade400,
        onTap: () => setState(() => _tool = _StudioTool.mock),
      ),
      _StudioTile(
        icon: Icons.rule,
        label: l.studioTf,
        color: Colors.cyan.shade700,
        onTap: () => setState(() => _tool = _StudioTool.tf),
      ),
      _StudioTile(
        icon: Icons.edit_note,
        label: l.studioEssay,
        color: Colors.purple.shade400,
        onTap: () => setState(() => _tool = _StudioTool.essay),
      ),
      _StudioTile(
        icon: Icons.insights_outlined,
        label: l.studioProgress,
        color: Colors.pink.shade400,
        onTap: () => setState(() => _tool = _StudioTool.progress),
      ),
      _StudioTile(
        icon: Icons.history,
        label: l.studioHistory,
        color: Colors.brown.shade400,
        onTap: () => setState(() => _tool = _StudioTool.history),
      ),
    ];
    return GridView.count(
      padding: const EdgeInsets.all(AppSpacing.sm),
      crossAxisCount: 4,
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      childAspectRatio: 2.1,
      children: tiles,
    );
  }
}

/// Etiqueta compacta del panel de estudio: mitad de ancho (4 por fila) y
/// un tercio de alto que la versión anterior, cada una con su propio color.
class _StudioTile extends StatelessWidget {
  const _StudioTile({
    required this.icon,
    required this.label,
    required this.color,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final dim = !enabled;
    final c = dim ? scheme.onSurfaceVariant : color;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: c.withValues(alpha: dim ? 0.06 : 0.12),
            border: Border.all(color: c.withValues(alpha: dim ? 0.18 : 0.40)),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: c),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dim ? scheme.onSurfaceVariant : null,
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

/// Progreso del temario: racha de estudio + barras de avance (secciones
/// trabajadas, flashcards dominadas, acierto en test).
class _ProgressView extends ConsumerWidget {
  const _ProgressView({required this.subjectId});

  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = context.colors;
    final streakAsync = ref.watch(studyStreakProvider);
    final nodes =
        ref.watch(indexNodesProvider(subjectId)).valueOrNull ?? const [];
    final aiIds = ref.watch(aiContentNodeIdsProvider(subjectId)).valueOrNull ??
        const <String>{};
    final cards =
        ref.watch(flashcardsProvider(subjectId)).valueOrNull ?? const [];
    final quiz =
        ref.watch(quizQuestionsProvider(subjectId)).valueOrNull ?? const [];

    final sections = nodes.where((n) => n.parentId != null).toList();
    final sectionsDone = sections.where((n) => aiIds.contains(n.id)).length;
    final mastered = cards.where((c) => c.reps >= 2).length;
    var seen = 0;
    var ok = 0;
    for (final q in quiz) {
      seen += q.timesSeen;
      ok += q.timesCorrect;
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // ─── Racha ───
        streakAsync.when(
          loading: () => const SizedBox(
            height: 24,
            child: Center(child: AppLoadingState()),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (s) => Row(
            children: [
              Icon(Icons.local_fire_department,
                  color: s.current > 0 ? Colors.orange : scheme.onSurfaceVariant,),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l.studyProgressStreak(s.current),
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              ..._last14(context, s.days),
            ],
          ),
        ),
        const Divider(height: AppSpacing.lg),
        _bar(context, l.studyProgressSections, sectionsDone, sections.length),
        const SizedBox(height: AppSpacing.md),
        _bar(context, l.studyProgressFlashcards, mastered, cards.length),
        const SizedBox(height: AppSpacing.md),
        _bar(context, l.studyProgressQuiz, ok, seen, asPercent: true),
      ],
    );
  }

  /// Mini-mapa de los últimos 14 días (punto lleno = estudiado).
  List<Widget> _last14(BuildContext context, Set<String> days) {
    final scheme = context.colors;
    final today = DateTime.now();
    final out = <Widget>[];
    for (var i = 13; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final ymd = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final on = days.contains(ymd);
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: on ? scheme.primary : scheme.outlineVariant,
            shape: BoxShape.circle,
          ),
        ),
      ),);
    }
    return out;
  }

  Widget _bar(
    BuildContext context,
    String label,
    int value,
    int total, {
    bool asPercent = false,
  }) {
    final scheme = context.colors;
    final frac = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;
    final trailing =
        asPercent ? '${(frac * 100).round()}%' : '$value/$total';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: context.textTheme.bodyMedium),
            ),
            Text(
              trailing,
              style: context.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: frac, minHeight: 8),
        ),
      ],
    );
  }
}


/// Historial de tests: gráfica de evolución de notas + lista de intentos con
/// fecha/hora, desglose y acciones para revisarlos o repetirlos (mismas
/// preguntas) y comparar la evolución.
class _HistoryView extends ConsumerWidget {
  const _HistoryView({required this.subjectId, required this.onSelectNode});

  final String subjectId;
  final ValueChanged<String> onSelectNode;

  static String _fmtDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = context.colors;
    final async = ref.watch(examAttemptsProvider(subjectId));
    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(l.studyViewError, textAlign: TextAlign.center),
        ),
      ),
      data: (attempts) {
        if (attempts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                l.studyHistoryEmpty,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }
        final chrono = attempts.reversed.toList(); // antiguos → recientes
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (attempts.length >= 2) ...[
              _chart(context, chrono),
              const Divider(height: AppSpacing.lg),
            ],
            for (final a in attempts) _tile(context, ref, a),
          ],
        );
      },
    );
  }

  /// Gráfica de barras de las notas (últimos 24 intentos, izq→der).
  Widget _chart(BuildContext context, List<ExamAttempt> chrono) {
    final l = context.l10n;
    final scheme = context.colors;
    const chartH = 86.0;
    final data =
        chrono.length > 24 ? chrono.sublist(chrono.length - 24) : chrono;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.studyHistoryEvolution,
          style:
              context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: chartH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final a in data)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message:
                          '${_fmtDateTime(a.createdAt)} · ${a.grade.toStringAsFixed(2)}/10',
                      child: Container(
                        height: (a.grade / 10 * chartH).clamp(4.0, chartH),
                        decoration: BoxDecoration(
                          color: a.grade >= 5
                              ? Colors.green.shade400
                              : scheme.error,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, ExamAttempt a) {
    final l = context.l10n;
    final scheme = context.colors;
    final gradeColor = a.grade >= 5 ? Colors.green.shade600 : scheme.error;
    final hasSnapshot = a.questions.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fmtDateTime(a.createdAt),
                    style: context.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${a.grade.toStringAsFixed(2)}/10',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: gradeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _miniChip(
                  context,
                  Icons.check,
                  Colors.green,
                  '${l.studyMockCorrect}: ${a.correct}',
                ),
                _miniChip(
                  context,
                  Icons.close,
                  scheme.error,
                  '${l.studyMockWrong}: ${a.wrong}',
                ),
                _miniChip(
                  context,
                  Icons.remove,
                  scheme.onSurfaceVariant,
                  '${l.studyMockBlank}: ${a.blank}',
                ),
              ],
            ),
            if (hasSnapshot) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _review(context, a),
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: Text(l.studyHistoryReview),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.tonalIcon(
                    onPressed: () => _repeat(context, ref, a),
                    icon: const Icon(Icons.replay, size: 16),
                    label: Text(l.studyHistoryRepeat),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniChip(
    BuildContext context,
    IconData icon,
    Color color,
    String text,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(text, style: context.textTheme.labelMedium),
      ],
    );
  }

  /// Revisa un intento pasado (solo lectura, sin volver a guardarlo).
  void _review(BuildContext context, ExamAttempt a) {
    showTestModal(
      context,
      TestRunnerDialog(
        subjectId: subjectId,
        questions: a.questions,
        timed: false,
        minutes: 0,
        penalty: a.penalty,
        onSelectNode: onSelectNode,
        initialAnswers: a.answers,
        startInReview: true,
        record: false,
      ),
    );
  }

  /// Repite el test con las MISMAS preguntas (orden barajado) para comparar la
  /// evolución; al terminar se guarda como un intento nuevo.
  void _repeat(BuildContext context, WidgetRef ref, ExamAttempt a) {
    final qs = List.of(a.questions)..shuffle();
    showTestModal(
      context,
      TestRunnerDialog(
        subjectId: subjectId,
        questions: qs,
        timed: a.timed,
        minutes: a.minutes,
        penalty: a.penalty,
        nodeIds: a.nodeIds,
        onSelectNode: onSelectNode,
      ),
    );
  }
}

/// Examen: cuenta atrás, ritmo de estudio y "modo pánico" (chuleta IA).
class _ExamView extends ConsumerStatefulWidget {
  const _ExamView({
    required this.subjectId,
    required this.examDate,
    required this.sectionCount,
  });

  final String subjectId;
  final DateTime? examDate;
  final int sectionCount;

  @override
  ConsumerState<_ExamView> createState() => _ExamViewState();
}

class _ExamViewState extends ConsumerState<_ExamView> {
  bool _busy = false;

  int? _daysToExam() {
    final d = widget.examDate;
    if (d == null) return null;
    final n = DateTime.now();
    final t0 = DateTime(n.year, n.month, n.day);
    final e0 = DateTime(d.year, d.month, d.day);
    return e0.difference(t0).inDays;
  }

  Future<void> _setDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.examDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 6),
    );
    if (picked == null) return;
    await ref.read(subjectsDataSourceProvider).setExamDate(widget.subjectId, picked);
    ref.invalidate(subjectsListProvider);
  }

  Future<void> _clearDate() async {
    await ref.read(subjectsDataSourceProvider).setExamDate(widget.subjectId, null);
    ref.invalidate(subjectsListProvider);
  }

  Future<void> _generateCram() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref.read(subjectsDataSourceProvider).generateCram(widget.subjectId);
      ref.invalidate(cramProvider(widget.subjectId));
    } on SubjectsException catch (e) {
      final detail =
          e.detail != null && e.detail!.isNotEmpty ? ': ${e.detail}' : '';
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          duration: const Duration(seconds: 8),
          content: Text('${l.studyViewError} (${e.code})$detail'),
        ),
      );
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
    final scheme = context.colors;
    final days = _daysToExam();
    final perDay = (days != null && days > 0 && widget.sectionCount > 0)
        ? (widget.sectionCount / days).ceil()
        : null;
    final cram = ref.watch(cramProvider(widget.subjectId));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // ─── Cuenta atrás ───
        if (days == null)
          Text(
            l.studyExamNoDate,
            style: context.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          )
        else ...[
          Text(
            days > 0
                ? l.studyExamIn(days)
                : (days == 0 ? l.studyExamToday : l.studyExamPast),
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
          if (perDay != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.studyExamPace(perDay),
                style: context.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _setDate,
              icon: const Icon(Icons.event_outlined, size: 16),
              label: Text(l.studyExamSetDate),
            ),
            if (widget.examDate != null)
              TextButton.icon(
                onPressed: _clearDate,
                icon: const Icon(Icons.event_busy_outlined, size: 16),
                label: Text(l.studyExamClear),
              ),
          ],
        ),
        const Divider(height: AppSpacing.lg),

        // ─── Modo pánico (chuleta) ───
        Row(
          children: [
            Icon(Icons.bolt, size: 18, color: scheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                l.studyPanicTitle,
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_busy)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.sm),
                  Text(l.studyGenerating, style: context.textTheme.bodySmall),
                ],
              ),
            ),
          )
        else
          cram.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: AppLoadingState()),
            ),
            error: (e, _) => AppErrorState(
              message: l.studyViewError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(cramProvider(widget.subjectId)),
              retryLabel: l.actionRetry,
            ),
            data: (content) {
              if (content == null || content.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.studyPanicEmpty,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PremiumButton(
                      label: l.studyPanicGenerate,
                      leadingIcon: Icons.bolt,
                      onPressed: _generateCram,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: l.studyExport,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        onPressed: () => downloadStudyText(
                          filename: 'chuleta.md',
                          text: content,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _generateCram,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(l.studyRegenerate),
                      ),
                    ],
                  ),
                  MarkdownText(content),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Guía de estudio: esquema estructurado (Markdown) del temario, generado por
/// IA y cacheado. Se regenera bajo demanda.
class _GuideView extends ConsumerStatefulWidget {
  const _GuideView({required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<_GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends ConsumerState<_GuideView> {
  bool _busy = false;
  bool _speaking = false;

  @override
  void dispose() {
    if (_speaking) ttsStop();
    super.dispose();
  }

  void _toggleSpeak(String content) {
    if (_speaking) {
      ttsStop();
      setState(() => _speaking = false);
    } else {
      ttsSpeak(content, lang: Localizations.localeOf(context).toLanguageTag());
      setState(() => _speaking = true);
    }
  }

  Future<void> _generate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(subjectsDataSourceProvider)
          .generateStudyGuide(widget.subjectId);
      ref.invalidate(studyGuideProvider(widget.subjectId));
    } on SubjectsException catch (e) {
      final detail =
          e.detail != null && e.detail!.isNotEmpty ? ': ${e.detail}' : '';
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          duration: const Duration(seconds: 8),
          content: Text('${l.studyViewError} (${e.code})$detail'),
        ),
      );
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
    final async = ref.watch(studyGuideProvider(widget.subjectId));
    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => AppErrorState(
        message: l.studyViewError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(studyGuideProvider(widget.subjectId)),
        retryLabel: l.actionRetry,
      ),
      data: (content) {
        if (content == null || content.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.studioGuideEmpty,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PremiumButton(
                    label: l.studioGuideGenerate,
                    leadingIcon: Icons.auto_awesome_outlined,
                    onPressed: _generate,
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: _speaking ? l.studyTtsStop : l.studyTtsListen,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _speaking
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_outlined,
                    size: 18,
                  ),
                  onPressed: () => _toggleSpeak(content),
                ),
                IconButton(
                  tooltip: l.studyExport,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  onPressed: () => downloadStudyText(
                    filename: 'guia-estudio.md',
                    text: content,
                  ),
                ),
                TextButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l.studyRegenerate),
                ),
              ],
            ),
            Expanded(child: ReaderFrame(child: MarkdownText(content))),
          ],
        );
      },
    );
  }
}

/// Cuestionario tipo test: corrección inmediata, explicación y puntuación.
///
/// Regla del producto: **la generación es siempre de la SECCIÓN ACTIVA del
/// índice** (no de todo el temario). La vista alterna entre "Esta sección" y
/// "Todo el temario" para repasar lo ya generado.
class _QuizView extends ConsumerStatefulWidget {
  const _QuizView({
    required this.subjectId,
    required this.activeNodeId,
    required this.activeNodeTitle,
  });

  final String subjectId;
  final String? activeNodeId;
  final String? activeNodeTitle;

  @override
  ConsumerState<_QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends ConsumerState<_QuizView> {
  bool _busy = false;
  int _index = 0;
  int? _selected;
  bool _answered = false;
  int _correct = 0;

  /// `true` = solo esta sección, `false` = todo el temario.
  bool _scopeSection = true;
  String? get _scopedNodeId => _scopeSection ? widget.activeNodeId : null;

  /// IDs de las preguntas falladas en la ronda actual (para "practicar
  /// falladas").
  final Set<String> _wrong = {};

  /// Si no es null, la ronda actual repasa solo este subconjunto (falladas).
  List<QuizQuestion>? _practice;

  void _reset() {
    _index = 0;
    _selected = null;
    _answered = false;
    _correct = 0;
    _wrong.clear();
    _practice = null;
  }

  /// Ordena por "debilidad" (peor dominio primero) usando las estadísticas
  /// persistidas; las no vistas quedan en medio. Determinista (estable).
  List<QuizQuestion> _byWeakness(List<QuizQuestion> qs) {
    double weakness(QuizQuestion q) =>
        q.timesSeen > 0 ? 1 - q.timesCorrect / q.timesSeen : 0.5;
    final list = [...qs];
    list.sort((a, b) {
      final cmp = weakness(b).compareTo(weakness(a));
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });
    return list;
  }

  Future<void> _generate() async {
    if (_busy) return;
    final nodeId = widget.activeNodeId;
    if (nodeId == null) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref.read(subjectsDataSourceProvider).generateQuiz(
            subjectId: widget.subjectId,
            nodeId: nodeId,
          );
      if (mounted) {
        setState(() {
          _scopeSection = true;
          _reset();
        });
      }
      ref
        ..invalidate(quizQuestionsProvider(widget.subjectId))
        ..invalidate(quizQuestionsScopedProvider(
          (subjectId: widget.subjectId, nodeId: nodeId),
        ),)
        ..invalidate(quizQuestionsScopedProvider(
          (subjectId: widget.subjectId, nodeId: null),
        ),);
    } on SubjectsException catch (e) {
      final detail =
          e.detail != null && e.detail!.isNotEmpty ? ': ${e.detail}' : '';
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          duration: const Duration(seconds: 8),
          content: Text('${l.studyViewError} (${e.code})$detail'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.studyViewError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _answer(QuizQuestion q, int i) {
    if (_answered) return;
    final correct = i == q.correctIndex;
    setState(() {
      _selected = i;
      _answered = true;
      if (correct) {
        _correct++;
      } else {
        _wrong.add(q.id);
      }
    });
    // Estadística best-effort (no bloquea el flujo).
    ref.read(subjectsDataSourceProvider).recordQuizAnswer(q, correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
    final scope = (subjectId: widget.subjectId, nodeId: _scopedNodeId);
    final async = ref.watch(quizQuestionsScopedProvider(scope));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scopeBar(context),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: AppLoadingState()),
            error: (e, _) => AppErrorState(
              message: l.studyViewError,
              detail: e.toString(),
              onRetry: () =>
                  ref.invalidate(quizQuestionsScopedProvider(scope)),
              retryLabel: l.actionRetry,
            ),
            data: (qs) => _quizContent(context, qs),
          ),
        ),
      ],
    );
  }

  Widget _scopeBar(BuildContext context) {
    final l = context.l10n;
    final hasActive = widget.activeNodeId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, label: Text(l.studyScopeSection)),
                ButtonSegment(value: false, label: Text(l.studyScopeAll)),
              ],
              selected: {_scopeSection},
              onSelectionChanged: (s) => setState(() {
                _scopeSection = s.first;
                _reset();
              }),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: hasActive ? l.studyRegenerate : l.studyPickSectionTooltip,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: hasActive ? _generate : null,
          ),
        ],
      ),
    );
  }

  Widget _quizContent(BuildContext context, List<QuizQuestion> qs) {
    final l = context.l10n;
    if (qs.isEmpty) {
      if (widget.activeNodeId == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_outlined,
                    size: 36, color: context.colors.onSurfaceVariant,),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l.studyPickSectionForQuiz,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _scopeSection
                    ? l.studioQuizEmptyForSection(widget.activeNodeTitle ?? '')
                    : l.studioQuizEmpty,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              PremiumButton(
                label: l.studioQuizGenerate,
                leadingIcon: Icons.auto_awesome_outlined,
                onPressed: _generate,
              ),
            ],
          ),
        ),
      );
    }
    final questions = _practice ?? _byWeakness(qs);
    if (_index >= questions.length) return _result(context, questions);

    final q = questions[_index];
    final last = _index == questions.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            '${_index + 1} / ${questions.length}',
            style: context.textTheme.labelMedium
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  q.question,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (var i = 0; i < q.options.length; i++)
                  _option(context, q, i),
                if (_answered && (q.explanation?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        q.explanation!,
                        style: context.textTheme.bodySmall
                            ?.copyWith(height: 1.4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_answered)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => setState(() {
                  _index++;
                  _selected = null;
                  _answered = false;
                }),
                child: Text(last ? l.studioQuizFinish : l.studioQuizNext),
              ),
            ),
          ),
      ],
    );
  }

  Widget _option(BuildContext context, QuizQuestion q, int i) {
    final scheme = context.colors;
    final isCorrect = i == q.correctIndex;
    final isSelected = i == _selected;
    Color border = scheme.outlineVariant;
    Color? bg;
    IconData icon = Icons.radio_button_unchecked;
    Color iconColor = scheme.onSurfaceVariant;
    if (_answered) {
      if (isCorrect) {
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.12);
        icon = Icons.check_circle;
        iconColor = Colors.green;
      } else if (isSelected) {
        border = scheme.error;
        bg = scheme.error.withValues(alpha: 0.12);
        icon = Icons.cancel;
        iconColor = scheme.error;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: _answered ? null : () => _answer(q, i),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(q.options[i], style: context.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _result(BuildContext context, List<QuizQuestion> questions) {
    final l = context.l10n;
    final total = questions.length;
    final failed =
        questions.where((q) => _wrong.contains(q.id)).toList(growable: false);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.studioQuizResult, style: context.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$_correct / $total',
              style: context.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: context.colors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                if (failed.isNotEmpty)
                  PremiumButton(
                    label: '${l.studioQuizPracticeFailed} (${failed.length})',
                    leadingIcon: Icons.fitness_center,
                    onPressed: () => setState(() {
                      _practice = failed;
                      _index = 0;
                      _selected = null;
                      _answered = false;
                      _correct = 0;
                      _wrong.clear();
                    }),
                  ),
                OutlinedButton.icon(
                  onPressed: () => setState(_reset),
                  icon: const Icon(Icons.replay, size: 16),
                  label: Text(l.studioQuizRetry),
                ),
                OutlinedButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l.studyRegenerate),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// Flashcards con repaso espaciado (flip + Otra vez/Bien/Fácil).
///
/// Regla del producto: **la generación es siempre de la SECCIÓN ACTIVA del
/// índice** (no de todo el temario). La vista, en cambio, permite alternar
/// entre "Esta sección" y "Todo el temario" para repasar agregadamente lo que
/// ya se generó por secciones.
class _FlashcardsView extends ConsumerStatefulWidget {
  const _FlashcardsView({
    required this.subjectId,
    required this.activeNodeId,
    required this.activeNodeTitle,
  });

  final String subjectId;
  final String? activeNodeId;
  final String? activeNodeTitle;

  @override
  ConsumerState<_FlashcardsView> createState() => _FlashcardsViewState();
}

class _FlashcardsViewState extends ConsumerState<_FlashcardsView> {
  bool _busy = false;
  bool _flipped = false;
  int _index = 0;

  /// `true` = solo esta sección, `false` = todo el temario.
  bool _scopeSection = true;

  String? get _scopedNodeId =>
      _scopeSection ? widget.activeNodeId : null;

  void _resetReview() {
    _index = 0;
    _flipped = false;
  }

  Future<void> _generate() async {
    if (_busy) return;
    final nodeId = widget.activeNodeId;
    if (nodeId == null) return; // botón estará deshabilitado
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref.read(subjectsDataSourceProvider).generateFlashcards(
            subjectId: widget.subjectId,
            nodeId: nodeId,
          );
      if (mounted) {
        setState(() {
          _scopeSection = true; // tras generar, mostramos la sección recién creada
          _resetReview();
        });
      }
      ref
        ..invalidate(flashcardsProvider(widget.subjectId))
        ..invalidate(flashcardsScopedProvider(
          (subjectId: widget.subjectId, nodeId: nodeId),
        ),)
        ..invalidate(flashcardsScopedProvider(
          (subjectId: widget.subjectId, nodeId: null),
        ),);
    } on SubjectsException catch (e) {
      final detail =
          e.detail != null && e.detail!.isNotEmpty ? ': ${e.detail}' : '';
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          duration: const Duration(seconds: 8),
          content: Text('${l.studyViewError} (${e.code})$detail'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.studyViewError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(Flashcard c, ReviewRating rating) async {
    try {
      await ref.read(subjectsDataSourceProvider).reviewFlashcard(c, rating);
    } catch (_) {
      // El repaso es best-effort: avanzamos igualmente.
    }
    if (mounted) {
      setState(() {
        _flipped = false;
        _index++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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

    final scope = (subjectId: widget.subjectId, nodeId: _scopedNodeId);
    final async = ref.watch(flashcardsScopedProvider(scope));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scopeBar(context),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: AppLoadingState()),
            error: (e, _) => AppErrorState(
              message: l.studyViewError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(flashcardsScopedProvider(scope)),
              retryLabel: l.actionRetry,
            ),
            data: (cards) => _content(context, cards),
          ),
        ),
      ],
    );
  }

  /// Barra superior: chip de scope (Esta sección / Todo el temario) +
  /// botón de regenerar (solo activo si hay sección activa).
  Widget _scopeBar(BuildContext context) {
    final l = context.l10n;
    final hasActive = widget.activeNodeId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, label: Text(l.studyScopeSection)),
                ButtonSegment(value: false, label: Text(l.studyScopeAll)),
              ],
              selected: {_scopeSection},
              onSelectionChanged: (s) => setState(() {
                _scopeSection = s.first;
                _resetReview();
              }),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: hasActive ? l.studyRegenerate : l.studyPickSectionTooltip,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: hasActive ? _generate : null,
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, List<Flashcard> cards) {
    final l = context.l10n;
    if (cards.isEmpty) {
      // Sin sección activa → CTA pidiendo seleccionarla.
      if (widget.activeNodeId == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_outlined,
                    size: 36, color: context.colors.onSurfaceVariant,),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l.studyPickSectionForCards,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _scopeSection
                    ? l.studioFlashEmptyForSection(
                        widget.activeNodeTitle ?? '',
                      )
                    : l.studioFlashEmpty,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              PremiumButton(
                label: l.studioFlashGenerate,
                leadingIcon: Icons.auto_awesome_outlined,
                onPressed: _generate,
              ),
            ],
          ),
        ),
      );
    }

    final done = _index >= cards.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            done ? '${cards.length} / ${cards.length}'
                : '${_index + 1} / ${cards.length}',
            style: context.textTheme.labelMedium
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: done ? _allDone(context) : _cardArea(context, cards[_index]),
        ),
      ],
    );
  }

  Widget _allDone(BuildContext context) {
    final l = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 40, color: context.colors.primary,),
          const SizedBox(height: AppSpacing.sm),
          Text(l.studioFlashAllDone, style: context.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          PremiumButton(
            label: l.studioFlashReviewAgain,
            leadingIcon: Icons.replay,
            onPressed: () {
              setState(_resetReview);
              ref.invalidate(flashcardsScopedProvider(
                (subjectId: widget.subjectId, nodeId: _scopedNodeId),
              ),);
            },
          ),
        ],
      ),
    );
  }

  Widget _cardArea(BuildContext context, Flashcard card) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: InkWell(
            onTap: () => setState(() => _flipped = !_flipped),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    card.front,
                    style: context.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (_flipped) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Divider(height: 1),
                    ),
                    SelectableText(
                      card.back,
                      style: context.textTheme.bodyMedium
                          ?.copyWith(height: 1.5),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(
                        l.studioFlashShowAnswer,
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_flipped)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _review(card, ReviewRating.again),
                    child: Text(l.studioFlashAgain),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _review(card, ReviewRating.good),
                    child: Text(l.studioFlashGood),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _review(card, ReviewRating.easy),
                    child: Text(l.studioFlashEasy),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Notas del usuario sobre la sección seleccionada (añadir / editar / borrar).
class _NotesView extends ConsumerStatefulWidget {
  const _NotesView({required this.nodeId, required this.subjectId});

  final String nodeId;
  final String subjectId;

  @override
  ConsumerState<_NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends ConsumerState<_NotesView> {
  final _newCtrl = TextEditingController();
  final _editCtrl = TextEditingController();
  String? _editingId;
  bool _busy = false;

  @override
  void dispose() {
    _newCtrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        content: Text(msg),
      ),
    );
  }

  Future<void> _add() async {
    final body = _newCtrl.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    try {
      await ref.read(subjectsDataSourceProvider).createAnnotation(
            subjectId: widget.subjectId,
            nodeId: widget.nodeId,
            body: body,
          );
      _newCtrl.clear();
      ref.invalidate(annotationsProvider(widget.nodeId));
    } catch (_) {
      _toast(l.studyViewError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEdit(String id) async {
    final body = _editCtrl.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    try {
      await ref.read(subjectsDataSourceProvider).updateAnnotation(id, body);
      if (mounted) setState(() => _editingId = null);
      ref.invalidate(annotationsProvider(widget.nodeId));
    } catch (_) {
      _toast(l.studyViewError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String id) async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.studyNoteDeleteTitle,
      body: l.studyNoteDeleteBody,
      confirmLabel: l.studyNoteDelete,
      danger: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(subjectsDataSourceProvider).deleteAnnotation(id);
      ref.invalidate(annotationsProvider(widget.nodeId));
    } catch (_) {
      _toast(l.studyViewError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(annotationsProvider(widget.nodeId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextField(
                controller: _newCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: l.studyNoteHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              PremiumButton(
                label: l.studyNoteAdd,
                leadingIcon: Icons.add,
                loading: _busy && _editingId == null,
                onPressed: _busy ? null : _add,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: AppLoadingState()),
            error: (e, _) => AppErrorState(
              message: l.studyViewError,
              detail: e.toString(),
              onRetry: () =>
                  ref.invalidate(annotationsProvider(widget.nodeId)),
              retryLabel: l.actionRetry,
            ),
            data: (notes) {
              if (notes.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      l.studyNoteEmpty,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.sm),
                itemCount: notes.length,
                itemBuilder: (ctx, i) => _noteTile(notes[i]),
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.xs),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _noteTile(Annotation note) {
    final l = context.l10n;
    final editing = _editingId == note.id;
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: editing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextField(
                  controller: _editCtrl,
                  minLines: 2,
                  maxLines: 6,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _editingId = null),
                      child: Text(l.actionCancel),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilledButton(
                      onPressed: _busy ? null : () => _saveEdit(note.id),
                      child: Text(l.actionSave),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    note.body,
                    style: context.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
                IconButton(
                  tooltip: l.studyNoteEdit,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _editingId = note.id;
                            _editCtrl.text = note.body;
                          }),
                ),
                IconButton(
                  tooltip: l.studyNoteDelete,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: _busy ? null : () => _delete(note.id),
                ),
              ],
            ),
    );
  }
}


// ════════════════════════════════════════════════════════════════════════════
// Preguntas a desarrollar — visor SIMPLE: lista scrollable con expansores.
// ════════════════════════════════════════════════════════════════════════════

/// Preguntas a desarrollar: selector de secciones + Generar/Regenerar +
/// `ListView` de tarjetas expansibles ("Ver respuesta" toggle). NO hay timer,
/// puntuación ni count: siempre devuelve TODO lo del banco para el ámbito.
class _EssayView extends ConsumerStatefulWidget {
  const _EssayView({required this.subjectId, required this.nodes});

  final String subjectId;
  final List<IndexNode> nodes;

  @override
  ConsumerState<_EssayView> createState() => _EssayViewState();
}

class _EssayViewState extends ConsumerState<_EssayView> {
  bool _busy = false;
  bool _all = true;
  final Set<String> _selected = {};

  Set<String> _scopeNodeIds() {
    if (_all) return widget.nodes.map((n) => n.id).toSet();
    final byParent = <String?, List<IndexNode>>{};
    for (final n in widget.nodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    final out = <String>{};
    void add(String id) {
      if (!out.add(id)) return;
      for (final c in byParent[id] ?? const <IndexNode>[]) {
        add(c.id);
      }
    }
    for (final id in _selected) {
      add(id);
    }
    return out;
  }

  List<EssayQuestion> _pool(List<EssayQuestion> bank) {
    if (_all) return bank;
    final scope = _scopeNodeIds();
    return bank
        .where((q) => q.nodeId != null && scope.contains(q.nodeId))
        .toList();
  }

  Future<void> _generate({bool force = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      final r = await ref.read(subjectsDataSourceProvider).generateEssayBank(
            subjectId: widget.subjectId,
            nodeIds: _all ? const [] : _scopeNodeIds().toList(),
            force: force,
          );
      ref.invalidate(essayQuestionsProvider(widget.subjectId));
      if (mounted) {
        final msg = r.pending > 0
            ? '${l.studyBankProgress(r.total, r.generated)} · '
                '${l.studyBankPending(r.pending)}'
            : l.studyBankProgress(r.total, r.generated);
        messenger.showSnackBar(
          SnackBar(duration: const Duration(seconds: 6), content: Text(msg)),
        );
      }
    } on SubjectsException catch (e) {
      final detail =
          e.detail != null && e.detail!.isNotEmpty ? ': ${e.detail}' : '';
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          duration: const Duration(seconds: 8),
          content: Text('${l.studyViewError} (${e.code})$detail'),
        ),
      );
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

    final scheme = context.colors;
    final bank =
        ref.watch(essayQuestionsProvider(widget.subjectId)).valueOrNull ??
            const <EssayQuestion>[];
    final sections = widget.nodes.where((n) => n.parentId != null).toList();
    final canGenerate = _all || _selected.isNotEmpty;
    final pool = _pool(bank);

    // Agrupar por sección, en el orden del índice (preservamos posición).
    final nodeOrder = <String, int>{
      for (var i = 0; i < widget.nodes.length; i++) widget.nodes[i].id: i,
    };
    final nodeTitleById = <String, String>{
      for (final n in widget.nodes) n.id: n.title,
    };
    final grouped = <String?, List<EssayQuestion>>{};
    for (final q in pool) {
      grouped.putIfAbsent(q.nodeId, () => []).add(q);
    }
    final groupKeys = grouped.keys.toList()
      ..sort((a, b) {
        final ai = a == null ? 1 << 30 : (nodeOrder[a] ?? 1 << 29);
        final bi = b == null ? 1 << 30 : (nodeOrder[b] ?? 1 << 29);
        return ai.compareTo(bi);
      });

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // ─── Secciones ───
        Row(
          children: [
            Expanded(
              child: Text(
                l.studyTestSections,
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(l.studyTestAll, style: context.textTheme.bodySmall),
            Switch(value: _all, onChanged: (v) => setState(() => _all = v)),
          ],
        ),
        if (!_all)
          for (final s in sections)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 4 + s.depth * 12.0),
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(s.id),
              title:
                  Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selected.add(s.id);
                } else {
                  _selected.remove(s.id);
                }
              }),
            ),
        const Divider(height: AppSpacing.lg),
        // ─── Acciones ───
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            PremiumButton(
              label: pool.isEmpty
                  ? l.studyEssayGenerate
                  : l.studyEssayRegenerate,
              leadingIcon: pool.isEmpty
                  ? Icons.auto_awesome_outlined
                  : Icons.refresh,
              onPressed:
                  canGenerate ? () => _generate(force: pool.isNotEmpty) : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (pool.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: Text(
                l.studyEssayEmpty,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else
          for (final key in groupKeys) ...[
            // Cabecera de sección (o "Sin sección" si el hash no se mapeó).
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                key == null
                    ? '—'
                    : (nodeTitleById[key] ?? '—'),
                style: context.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            for (var i = 0; i < grouped[key]!.length; i++)
              _EssayTile(
                index: i,
                question: grouped[key]![i],
              ),
          ],
      ],
    );
  }
}

/// Tarjeta de una pregunta a desarrollar: pregunta arriba, toggle "Ver / Ocultar
/// respuesta" que despliega la respuesta modelo en `SelectableText` (copy/paste
/// amigable para el estudiante).
class _EssayTile extends StatefulWidget {
  const _EssayTile({required this.index, required this.question});

  final int index;
  final EssayQuestion question;

  @override
  State<_EssayTile> createState() => _EssayTileState();
}

class _EssayTileState extends State<_EssayTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final q = widget.question;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              '${widget.index + 1}. ${q.question}',
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(
                  _open ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 16,
                ),
                label: Text(
                  _open ? l.studyEssayHideAnswer : l.studyEssayShowAnswer,
                ),
              ),
            ),
            if (_open) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  q.answer,
                  style: context.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
