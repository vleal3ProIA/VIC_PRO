import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';

import '../../application/incidents_providers.dart';
import '../../domain/incident.dart';
import '../incident_visuals.dart';

/// Banner que se monta sobre el `PrivateShell` cuando hay un incidente
/// activo de severidad >= major (o maintenance). Es ESTRECHO (40px) y
/// fijo arriba — quita lo mínimo de espacio del contenido.
///
/// Por qué severity-aware: si hay 5 minor incidents simultáneos no
/// queremos llenar la app de banners; basta con la página /status.
/// Solo cosas que el usuario debe SABER ahora (auth caída, billing
/// caído, ventana de mantenimiento).
///
/// Si hay varios incidentes que merecen banner, pintamos el más severo
/// (crítico > major > maintenance).
class MaintenanceBanner extends ConsumerWidget {
  const MaintenanceBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(activeIncidentsProvider);
    final incident = _pickBannerWorthy(async.valueOrNull ?? const []);
    if (incident == null) return const SizedBox.shrink();

    final v = incidentSeverityVisuals(context, incident.severity);
    return Material(
      color: v.color.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () => context.goNamed(RouteNames.status),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: v.color.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(v.icon, color: v.color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${v.label(l)} · ',
                        style: TextStyle(
                          color: v.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: incident.title,
                        style: TextStyle(color: context.colors.onSurface),
                      ),
                    ],
                  ),
                  style: context.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l.maintenanceBannerCta,
                style: context.textTheme.labelSmall?.copyWith(
                  color: v.color,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Devuelve el incidente más severo entre los que merecen banner.
  Incident? _pickBannerWorthy(List<Incident> incidents) {
    Incident? best;
    int bestRank = -1;
    for (final i in incidents) {
      if (!i.warrantsBanner) continue;
      final rank = _severityRank(i.severity);
      if (rank > bestRank) {
        bestRank = rank;
        best = i;
      }
    }
    return best;
  }

  int _severityRank(IncidentSeverity s) {
    switch (s) {
      case IncidentSeverity.critical:
        return 3;
      case IncidentSeverity.major:
        return 2;
      case IncidentSeverity.maintenance:
        return 1;
      case IncidentSeverity.minor:
        return 0; // never reaches here (warrantsBanner = false).
    }
  }
}
