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

import '../../application/subjects_providers.dart';
import '../../data/subjects_datasource.dart';
import '../../domain/subject.dart';
import '../util/file_picker_web.dart';
import '../util/study_export.dart';
import '../util/study_tts.dart';

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

  void _openSources(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: _DocumentsPanel(subjectId: subject.id),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final locked = subject.indexLocked;
    final ready = subject.indexReady && orderedNodes.isNotEmpty;

    final actions = <Widget>[
      IconButton(
        tooltip: l.subjectDocsTitle,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.source_outlined, size: 18),
        onPressed: () => _openSources(context),
      ),
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

class _ContentColumn extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l = context.l10n;
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

    return PremiumCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: DefaultTabController(
        length: 4,
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
                nodeTitle ?? '',
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
                Tab(text: l.studyTabChat),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _NodeView(
                    nodeId: nodeId!,
                    kind: 'original',
                    subjectId: subjectId,
                  ),
                  _NodeView(
                    nodeId: nodeId!,
                    kind: 'explained',
                    subjectId: subjectId,
                  ),
                  _NodeView(
                    nodeId: nodeId!,
                    kind: 'summary',
                    subjectId: subjectId,
                  ),
                  _ChatView(
                    key: ValueKey('chat_$subjectId'),
                    subjectId: subjectId,
                    nodeId: nodeId,
                    nodes: nodes,
                    onSelectNode: onSelectNode,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: markdown
          ? MarkdownText(content)
          : SelectableText(
              content,
              style: context.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
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
  progress,
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
    final inProgress = _tool == _StudioTool.progress;

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
      leading = Icons.timer_outlined;
    } else if (inProgress) {
      title = l.studioProgress;
      leading = Icons.insights_outlined;
    } else {
      title = l.studioTitle;
      leading = Icons.auto_awesome;
    }

    final Widget body;
    if (inNotes) {
      body = _NotesView(nodeId: widget.nodeId!, subjectId: widget.subjectId);
    } else if (inFlash) {
      body = _FlashcardsView(subjectId: widget.subjectId);
    } else if (inMind) {
      body = _MindMapView(
        subjectId: widget.subjectId,
        selectedId: widget.nodeId,
        onSelectNode: widget.onSelectNode,
      );
    } else if (inQuiz) {
      body = _QuizView(subjectId: widget.subjectId);
    } else if (inGuide) {
      body = _GuideView(subjectId: widget.subjectId);
    } else if (inExam) {
      body = _ExamView(
        subjectId: widget.subjectId,
        examDate: widget.examDate,
        sectionCount: widget.sectionCount,
      );
    } else if (inMock) {
      body = _MockExamView(
        subjectId: widget.subjectId,
        nodes: widget.nodes,
        onSelectNode: widget.onSelectNode,
      );
    } else if (inProgress) {
      body = _ProgressView(subjectId: widget.subjectId);
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
            inProgress)
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
        enabled: canNotes,
        onTap: canNotes
            ? () => setState(() => _tool = _StudioTool.notes)
            : null,
      ),
      _StudioTile(
        icon: Icons.style_outlined,
        label: l.studioFlashcards,
        onTap: () => setState(() => _tool = _StudioTool.flashcards),
      ),
      _StudioTile(
        icon: Icons.quiz_outlined,
        label: l.studioQuiz,
        onTap: () => setState(() => _tool = _StudioTool.quiz),
      ),
      _StudioTile(
        icon: Icons.hub_outlined,
        label: l.studioMindmap,
        onTap: () => setState(() => _tool = _StudioTool.mindmap),
      ),
      _StudioTile(
        icon: Icons.menu_book_outlined,
        label: l.studioGuide,
        onTap: () => setState(() => _tool = _StudioTool.guide),
      ),
      _StudioTile(
        icon: Icons.event_outlined,
        label: l.studyExamLabel,
        onTap: () => setState(() => _tool = _StudioTool.exam),
      ),
      _StudioTile(
        icon: Icons.timer_outlined,
        label: l.studioMock,
        onTap: () => setState(() => _tool = _StudioTool.mock),
      ),
      _StudioTile(
        icon: Icons.insights_outlined,
        label: l.studioProgress,
        onTap: () => setState(() => _tool = _StudioTool.progress),
      ),
    ];
    return GridView.count(
      padding: const EdgeInsets.all(AppSpacing.sm),
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.4,
      children: tiles,
    );
  }
}

class _StudioTile extends StatelessWidget {
  const _StudioTile({
    required this.icon,
    required this.label,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final dim = !enabled;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 22,
              color: dim ? scheme.onSurfaceVariant : scheme.primary,
            ),
            const Spacer(),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: dim ? scheme.onSurfaceVariant : null,
              ),
            ),
          ],
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

/// Simulacro de examen: cronometrado, sin feedback hasta el final, con
/// penalización (aciertos − errores/3) y nota sobre 10. Reusa las preguntas del
/// cuestionario.
enum _MockPhase { config, running, done }

class _MockExamView extends ConsumerStatefulWidget {
  const _MockExamView({
    required this.subjectId,
    required this.nodes,
    required this.onSelectNode,
  });

  final String subjectId;
  final List<IndexNode> nodes;
  final ValueChanged<String> onSelectNode;

  @override
  ConsumerState<_MockExamView> createState() => _MockExamViewState();
}

class _MockExamViewState extends ConsumerState<_MockExamView> {
  _MockPhase _phase = _MockPhase.config;
  bool _busy = false;

  // Configuración del test.
  bool _all = true;
  final Set<String> _selected = {};
  int _count = 10;
  bool _timed = false;
  int _minutes = 20;
  bool _penalty = true;

  // Ejecución.
  List<QuizQuestion> _qs = [];
  List<int?> _answers = [];
  int _cur = 0;
  int _elapsed = 0;
  Timer? _timer;
  bool _review = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _totalSecs => _minutes * 60;

  String _fmt(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _start(List<QuizQuestion> qs) {
    _timer?.cancel();
    setState(() {
      _qs = List.of(qs);
      _answers = List<int?>.filled(_qs.length, null);
      _cur = 0;
      _elapsed = 0;
      _review = false;
      _phase = _MockPhase.running;
    });
    if (_timed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          _timer?.cancel();
          return;
        }
        setState(() => _elapsed++);
        if (_elapsed >= _totalSecs) _finish();
      });
    }
  }

  void _finish() {
    _timer?.cancel();
    unawaited(ref.read(subjectsDataSourceProvider).recordStudyToday());
    if (mounted) setState(() => _phase = _MockPhase.done);
  }

  Future<void> _generate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref.read(subjectsDataSourceProvider).generateExam(
            subjectId: widget.subjectId,
            nodeIds: _all ? const [] : _selected.toList(),
            count: _count,
          );
      ref.invalidate(examQuestionsProvider(widget.subjectId));
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
    if (_phase == _MockPhase.running) return _running(context);
    if (_phase == _MockPhase.done) return _results(context);
    return _config(context);
  }

  Widget _config(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final bank =
        ref.watch(examQuestionsProvider(widget.subjectId)).valueOrNull ??
            const <QuizQuestion>[];
    final sections = widget.nodes.where((n) => n.parentId != null).toList();
    final canGenerate = _all || _selected.isNotEmpty;

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
              title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selected.add(s.id);
                } else {
                  _selected.remove(s.id);
                }
              }),
            ),
        const Divider(height: AppSpacing.lg),
        // ─── Nº de preguntas ───
        Row(
          children: [
            Expanded(child: Text(l.studyTestCount)),
            DropdownButton<int>(
              value: _count,
              items: [5, 10, 20, 30, 40]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                  .toList(),
              onChanged: (v) => setState(() => _count = v ?? 10),
            ),
          ],
        ),
        // ─── Tiempo ───
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.studyTestTimed),
          value: _timed,
          onChanged: (v) => setState(() => _timed = v),
        ),
        if (_timed)
          Row(
            children: [
              Expanded(child: Text(l.studyTestMinutes)),
              DropdownButton<int>(
                value: _minutes,
                items: [5, 10, 20, 30, 45, 60]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) => setState(() => _minutes = v ?? 20),
              ),
            ],
          ),
        // ─── Penalización ───
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.studyTestPenalty),
          value: _penalty,
          onChanged: (v) => setState(() => _penalty = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (bank.isNotEmpty)
          Text(
            l.studyTestBank(bank.length),
            style: context.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            PremiumButton(
              label: bank.isEmpty ? l.studyTestGenerate : l.studyTestRegenerate,
              leadingIcon: Icons.auto_awesome_outlined,
              onPressed: canGenerate ? _generate : null,
            ),
            if (bank.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _start(bank),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(l.studyTestStart),
              ),
          ],
        ),
      ],
    );
  }

  Widget _running(BuildContext context) {
    final l = context.l10n;
    final q = _qs[_cur];
    final answered = _answers.where((a) => a != null).length;
    final remaining = (_totalSecs - _elapsed).clamp(0, _totalSecs);
    final last = _cur == _qs.length - 1;
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
          child: Row(
            children: [
              if (_timed) ...[
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: remaining <= 30 ? context.colors.error : null,
                ),
                const SizedBox(width: 4),
                Text(_fmt(remaining), style: context.textTheme.labelMedium),
              ],
              const Spacer(),
              Text(
                '${_cur + 1}/${_qs.length} · $answered',
                style: context.textTheme.labelMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
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
                  _optionTile(
                    context,
                    text: q.options[i],
                    selected: _answers[_cur] == i,
                    onTap: () => setState(
                      () => _answers[_cur] = _answers[_cur] == i ? null : i,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              IconButton(
                onPressed: _cur > 0 ? () => setState(() => _cur--) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: !last ? () => setState(() => _cur++) : null,
                icon: const Icon(Icons.chevron_right),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _finish,
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: Text(l.studyMockFinish),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _results(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    var correct = 0;
    var wrong = 0;
    var blank = 0;
    for (var i = 0; i < _qs.length; i++) {
      final a = _answers[i];
      if (a == null) {
        blank++;
      } else if (a == _qs[i].correctIndex) {
        correct++;
      } else {
        wrong++;
      }
    }
    final total = _qs.length;
    final raw = _penalty ? correct - wrong / 3 : correct.toDouble();
    final grade = total == 0 ? 0.0 : (raw < 0 ? 0.0 : raw / total * 10);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Center(
          child: Column(
            children: [
              Text(l.studioQuizResult, style: context.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${grade.toStringAsFixed(2)} / 10',
                style: context.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  Chip(
                    avatar: const Icon(Icons.check, size: 14, color: Colors.green),
                    label: Text('${l.studyMockCorrect}: $correct'),
                  ),
                  Chip(
                    avatar: Icon(Icons.close, size: 14, color: scheme.error),
                    label: Text('${l.studyMockWrong}: $wrong'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.remove, size: 14),
                    label: Text('${l.studyMockBlank}: $blank'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _review = !_review),
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: Text(l.studyMockReview),
                  ),
                  PremiumButton(
                    label: l.studioQuizRetry,
                    leadingIcon: Icons.replay,
                    onPressed: () => setState(() => _phase = _MockPhase.config),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_review) ...[
          const Divider(height: AppSpacing.lg),
          for (var i = 0; i < _qs.length; i++) _reviewItem(context, i),
        ],
      ],
    );
  }

  Widget _reviewItem(BuildContext context, int i) {
    final l = context.l10n;
    final scheme = context.colors;
    final q = _qs[i];
    final mine = _answers[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${i + 1}. ${q.question}',
            style: context.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (var j = 0; j < q.options.length; j++)
            _optionTile(
              context,
              text: q.options[j],
              selected: mine == j,
              correct: j == q.correctIndex,
              readOnly: true,
            ),
          if (q.explanation?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  q.explanation!,
                  style: context.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ),
          if (q.nodeId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => widget.onSelectNode(q.nodeId!),
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: Text(l.studyTestViewInMaterial),
              ),
            ),
        ],
      ),
    );
  }

  Widget _optionTile(
    BuildContext context, {
    required String text,
    required bool selected,
    bool? correct,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    final scheme = context.colors;
    Color border = scheme.outlineVariant;
    Color? bg;
    if (readOnly) {
      if (correct ?? false) {
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.12);
      } else if (selected) {
        border = scheme.error;
        bg = scheme.error.withValues(alpha: 0.12);
      }
    } else if (selected) {
      border = scheme.primary;
      bg = scheme.primary.withValues(alpha: 0.10);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
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
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(text, style: context.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: MarkdownText(content),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Cuestionario tipo test: responder preguntas con corrección inmediata,
/// explicación y puntuación final.
class _QuizView extends ConsumerStatefulWidget {
  const _QuizView({required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<_QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends ConsumerState<_QuizView> {
  bool _busy = false;
  int _index = 0;
  int? _selected;
  bool _answered = false;
  int _correct = 0;

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
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(subjectsDataSourceProvider)
          .generateQuiz(subjectId: widget.subjectId);
      if (mounted) setState(_reset);
      ref.invalidate(quizQuestionsProvider(widget.subjectId));
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
    final async = ref.watch(quizQuestionsProvider(widget.subjectId));
    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => AppErrorState(
        message: l.studyViewError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(quizQuestionsProvider(widget.subjectId)),
        retryLabel: l.actionRetry,
      ),
      data: (qs) {
        if (qs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.studioQuizEmpty,
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
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    '${_index + 1} / ${questions.length}',
                    style: context.textTheme.labelMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l.studyRegenerate,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _generate,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
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
      },
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

/// Mapa mental: el ÍNDICE del temario como árbol interactivo (izquierda ->
/// derecha) con zoom/pan, ramas plegables y nodos clicables (saltan a la
/// sección). Se deriva del índice real, así que es fiel al temario.
class _MindMapView extends ConsumerStatefulWidget {
  const _MindMapView({
    required this.subjectId,
    required this.selectedId,
    required this.onSelectNode,
  });

  final String subjectId;
  final String? selectedId;
  final ValueChanged<String> onSelectNode;

  @override
  ConsumerState<_MindMapView> createState() => _MindMapViewState();
}

class _MindMapViewState extends ConsumerState<_MindMapView> {
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

/// Flashcards del temario con repaso espaciado (flip + Otra vez/Bien/Fácil).
class _FlashcardsView extends ConsumerStatefulWidget {
  const _FlashcardsView({required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<_FlashcardsView> createState() => _FlashcardsViewState();
}

class _FlashcardsViewState extends ConsumerState<_FlashcardsView> {
  bool _busy = false;
  bool _flipped = false;
  int _index = 0;

  Future<void> _generate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(subjectsDataSourceProvider)
          .generateFlashcards(subjectId: widget.subjectId);
      if (mounted) {
        setState(() {
            _index = 0;
            _flipped = false;
          });
      }
      ref.invalidate(flashcardsProvider(widget.subjectId));
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

    final async = ref.watch(flashcardsProvider(widget.subjectId));
    return async.when(
      loading: () => const Center(child: AppLoadingState()),
      error: (e, _) => AppErrorState(
        message: l.studyViewError,
        detail: e.toString(),
        onRetry: () => ref.invalidate(flashcardsProvider(widget.subjectId)),
        retryLabel: l.actionRetry,
      ),
      data: (cards) {
        if (cards.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.studioFlashEmpty,
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
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    done ? '${cards.length} / ${cards.length}'
                        : '${_index + 1} / ${cards.length}',
                    style: context.textTheme.labelMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l.studyRegenerate,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _generate,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: done
                  ? _allDone(context)
                  : _cardArea(context, cards[_index]),
            ),
          ],
        );
      },
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
              setState(() {
                _index = 0;
                _flipped = false;
              });
              ref.invalidate(flashcardsProvider(widget.subjectId));
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

// ─────────────────────────── Documentos / fuentes ───────────────────────────

/// Panel de documentos de un temario: lista con estado + subir archivo.
/// Hace polling mientras algún documento esté en proceso.
class _DocumentsPanel extends ConsumerStatefulWidget {
  const _DocumentsPanel({required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<_DocumentsPanel> createState() => _DocumentsPanelState();
}

class _DocumentsPanelState extends ConsumerState<_DocumentsPanel> {
  Timer? _poll;
  bool _uploading = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPolling(List<SubjectDocument> docs) {
    final anyInProgress = docs.any((d) => d.inProgress);
    if (anyInProgress) {
      if (_poll == null || !_poll!.isActive) {
        _poll = Timer.periodic(const Duration(seconds: 4), (_) {
          if (!mounted) {
            _poll?.cancel();
            return;
          }
          ref.invalidate(subjectDocumentsProvider(widget.subjectId));
        });
      }
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _upload() async {
    if (_uploading) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errBg = Theme.of(context).colorScheme.error;
    final picked = await pickFile();
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(subjectsDataSourceProvider).uploadDocument(
            subjectId: widget.subjectId,
            file: picked,
          );
      ref.invalidate(subjectDocumentsProvider(widget.subjectId));
      messenger.showSnackBar(SnackBar(content: Text(l.subjectUploaded)));
    } on SubjectsException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errBg,
          content: Text('${l.subjectUploadError} (${e.code})'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: errBg, content: Text(l.subjectUploadError)),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteDoc(SubjectDocument doc) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(subjectsDataSourceProvider).deleteDocument(doc);
    ref.invalidate(subjectDocumentsProvider(widget.subjectId));
    if (mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l.subjectDocDeleted)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(subjectDocumentsProvider(widget.subjectId));
    async.whenData(_syncPolling);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.subjectDocsTitle,
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _uploading ? null : _upload,
              icon: _uploading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(l.subjectUpload),
            ),
          ],
        ),
        if (_uploading)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(6)),
              child: LinearProgressIndicator(minHeight: 4),
            ),
          ),
        const Divider(height: AppSpacing.lg),
        Flexible(
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: AppLoadingState(),
            ),
            error: (e, _) => AppErrorState(
              message: l.subjectsLoadError,
              detail: e.toString(),
              onRetry: () =>
                  ref.invalidate(subjectDocumentsProvider(widget.subjectId)),
              retryLabel: l.actionRetry,
            ),
            data: (docs) {
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    l.subjectNoDocs,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return ListView(
                shrinkWrap: true,
                children: [
                  for (final d in docs) _DocRow(doc: d, onDelete: _deleteDoc),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.doc, required this.onDelete});

  final SubjectDocument doc;
  final Future<void> Function(SubjectDocument) onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.fileName ?? doc.storagePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium,
                ),
                if (doc.inProgress)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  ),
                if (doc.status == DocStatus.failed && doc.error != null)
                  Text(
                    doc.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: scheme.error),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatusChip(status: doc.status),
          IconButton(
            tooltip: l.aiDeleteCta,
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => onDelete(doc),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final DocStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    switch (status) {
      case DocStatus.queued:
        return PremiumBadge(
          label: l.docStatusQueued,
          variant: PremiumBadgeVariant.neutral,
          dense: true,
        );
      case DocStatus.processing:
        return PremiumBadge(
          label: l.docStatusProcessing,
          variant: PremiumBadgeVariant.info,
          dense: true,
        );
      case DocStatus.ready:
        return PremiumBadge(
          label: l.docStatusReady,
          variant: PremiumBadgeVariant.success,
          dense: true,
        );
      case DocStatus.failed:
        return PremiumBadge(
          label: l.docStatusFailed,
          variant: PremiumBadgeVariant.error,
          dense: true,
        );
    }
  }
}
