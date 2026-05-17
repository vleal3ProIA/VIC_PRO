import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/features/audit/domain/audit_log_entry.dart';
import 'package:myapp/features/audit/presentation/activity_day_grouper.dart';
import 'package:myapp/features/audit/presentation/audit_event_visuals.dart';

/// `/activity` — timeline visual de la actividad del propio usuario.
///
/// **Diferencia con `/audit-log`**: misma data, distinta presentación.
/// Activity feed es para uso diario del usuario (revisar qué pasó hoy,
/// qué cambió el equipo); audit log es la vista técnica para
/// compliance / auditoría (lista plana, sin filtros).
///
/// Eventualmente, cuando `audit_logs` tenga `tenant_id`, esta pantalla
/// expandirá a "mostrar también acciones de otros miembros del tenant"
/// — entonces el AppBar mostrará dos tabs "Mio" / "Equipo".
class ActivityFeedPage extends ConsumerStatefulWidget {
  const ActivityFeedPage({super.key});

  @override
  ConsumerState<ActivityFeedPage> createState() => _ActivityFeedPageState();
}

class _ActivityFeedPageState extends ConsumerState<ActivityFeedPage> {
  /// Categoría seleccionada en el filtro. `null` = todas.
  AuditEventCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final entriesAsync = ref.watch(myAuditLogProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.accountSettings),
        ),
        title: Text(l.activityTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myAuditLogProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: entriesAsync.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.activityLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(myAuditLogProvider),
              retryLabel: l.actionRetry,
            ),
            data: (entries) {
              // Filter chips siempre visibles (incluso con lista
              // vacía) -- así el user ve que hay opciones aunque su
              // filtro actual no devuelva nada.
              final filtered = _filter == null
                  ? entries
                  : entries
                      .where((e) => categoryFor(e.event) == _filter)
                      .toList(growable: false);

              return Column(
                children: [
                  _Filters(
                    selected: _filter,
                    onChanged: (c) => setState(() => _filter = c),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? AppEmptyState(
                            icon: Icons.history_toggle_off_outlined,
                            title: _filter == null
                                ? l.activityEmptyTitle
                                : l.activityFilteredEmptyTitle,
                            message: _filter == null
                                ? l.activityEmptyBody
                                : l.activityFilteredEmptyBody,
                          )
                        : _Timeline(entries: filtered),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Filters ─────────────────────────────

class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onChanged});
  final AuditEventCategory? selected;
  final ValueChanged<AuditEventCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: Text(l.activityFilterAll),
              selected: selected == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final cat in AuditEventCategory.values) ...[
              const SizedBox(width: 8),
              FilterChip(
                avatar: Icon(
                  _iconForCategory(cat),
                  size: 16,
                  color: colorForCategory(context.colors, cat),
                ),
                label: Text(labelForCategory(l, cat)),
                selected: selected == cat,
                onSelected: (_) => onChanged(cat),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconForCategory(AuditEventCategory cat) {
    switch (cat) {
      case AuditEventCategory.auth:
        return Icons.login;
      case AuditEventCategory.account:
        return Icons.manage_accounts_outlined;
      case AuditEventCategory.mfa:
        return Icons.shield_outlined;
      case AuditEventCategory.passkey:
        return Icons.fingerprint;
      case AuditEventCategory.other:
        return Icons.history;
    }
  }
}

// ───────────────────────────── Timeline ─────────────────────────────

class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});
  final List<AuditLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final groups = groupByDay(entries, l, localeCode);
    // Aplanamos los grupos en una lista de items (header o tile) para
    // pintar con un ListView.builder eficiente.
    final items = <_Item>[];
    for (final g in groups) {
      items.add(_Item.header(g.label));
      for (var i = 0; i < g.entries.length; i++) {
        items.add(_Item.entry(g.entries[i], isLastInGroup: i == g.entries.length - 1));
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item.isHeader) return _DayHeader(label: item.headerLabel!);
        return _TimelineTile(
          entry: item.entry!,
          isLastInGroup: item.isLastInGroup,
        );
      },
    );
  }
}

/// Item flat: o un header de día, o una entry. Pequeño helper para que
/// el `ListView.builder` no tenga que hacer cálculos de índices anidados.
class _Item {
  _Item.header(this.headerLabel)
      : entry = null,
        isLastInGroup = false;
  _Item.entry(this.entry, {required this.isLastInGroup}) : headerLabel = null;

  final String? headerLabel;
  final AuditLogEntry? entry;
  final bool isLastInGroup;
  bool get isHeader => headerLabel != null;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(
        label,
        style: context.textTheme.labelMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.entry, required this.isLastInGroup});
  final AuditLogEntry entry;
  final bool isLastInGroup;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = context.colors;
    final cat = categoryFor(entry.event);
    final color = colorForCategory(scheme, cat);
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).languageCode);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Línea vertical + dot — el dot del primer item del grupo no
          // tiene línea encima (visualmente "inicia" la cadena del día).
          SizedBox(
            width: 40,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                ),
                if (!isLastInGroup)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  dense: true,
                  leading: Icon(iconForAuditEvent(entry.event), color: color),
                  title: Text(labelForAuditEvent(l, entry.event)),
                  subtitle: Text(timeFmt.format(entry.occurredAt.toLocal())),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
