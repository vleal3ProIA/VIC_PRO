import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../application/incidents_providers.dart';
import '../../domain/incident.dart';
import '../incident_visuals.dart';

/// `/status` — página PÚBLICA (sin auth) que muestra el estado
/// operativo de la app. Estructura:
///
///   ┌──────────────────────────────────────┐
///   │  [✓] All systems operational         │  ← big badge
///   ├──────────────────────────────────────┤
///   │  Active incidents                    │  ← solo si hay
///   │    • [chip] title — started X ago    │
///   │      body                            │
///   ├──────────────────────────────────────┤
///   │  History (last 30 days)              │
///   │    Mon 14 May — Resolved, 2 events   │
///   └──────────────────────────────────────┘
///
/// Como es publica, lleva un AppBar minimo con vuelta a /welcome y un
/// disclaimer "no auth required".
class StatusPage extends ConsumerWidget {
  const StatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final activeAsync = ref.watch(activeIncidentsProvider);
    final historyAsync = ref.watch(incidentsHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.welcome),
        ),
        title: Text(l.statusPageTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref
                ..invalidate(activeIncidentsProvider)
                ..invalidate(incidentsHistoryProvider);
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: activeAsync.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l.statusLoadError,
                style: TextStyle(color: context.colors.error),
              ),
            ),
            data: (active) {
              final overall = computeOverallStatus(active);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                children: [
                  _OverallBadge(status: overall),
                  const SizedBox(height: 24),
                  if (active.isNotEmpty) ...[
                    _SectionHeader(l.statusActiveIncidents),
                    for (final i in active)
                      _IncidentCard(incident: i, highlighted: true),
                    const SizedBox(height: 16),
                  ],
                  _SectionHeader(l.statusHistory),
                  historyAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.statusLoadError,
                        style: TextStyle(color: context.colors.error),
                      ),
                    ),
                    data: (history) {
                      // Filtramos los que ya están en "active" para no
                      // duplicarlos en el histórico.
                      final activeIds = active.map((e) => e.id).toSet();
                      final past = history
                          .where((i) => !activeIds.contains(i.id))
                          .toList();
                      if (past.isEmpty) {
                        return AppEmptyState(
                          icon: Icons.history,
                          title: l.statusHistoryEmptyTitle,
                          message: l.statusHistoryEmptyBody,
                        );
                      }
                      return Column(
                        children: [
                          for (final i in past) _IncidentCard(incident: i),
                        ],
                      );
                    },
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

class _OverallBadge extends StatelessWidget {
  const _OverallBadge({required this.status});
  final OverallStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final v = overallStatusVisuals(context, status);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: v.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: v.color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(v.icon, color: v.color, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              v.label(l),
              style: context.textTheme.titleLarge?.copyWith(
                color: v.color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: context.textTheme.labelMedium?.copyWith(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident, this.highlighted = false});

  final Incident incident;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();
    final statusV = incidentStatusVisuals(context, incident.status);
    final sevV = incidentSeverityVisuals(context, incident.severity);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: highlighted
          ? sevV.color.withValues(alpha: 0.08)
          : null,
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: sevV.color.withValues(alpha: 0.4),
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Línea 1: chips de severidad y status.
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Chip(
                  icon: sevV.icon,
                  label: sevV.label(l),
                  color: sevV.color,
                ),
                _Chip(
                  icon: statusV.icon,
                  label: statusV.label(l),
                  color: statusV.color,
                ),
                for (final c in incident.components)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.colors.outlineVariant),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      c,
                      style: context.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              incident.title,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            // Fechas.
            Text(
              incident.isActive
                  ? l.statusStartedAt(fmt.format(incident.startedAt.toLocal()))
                  : l.statusResolvedAt(
                      fmt.format(incident.resolvedAt!.toLocal()),
                    ),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            if (incident.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                incident.body,
                style: context.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
