// ============================================================================
// PostHog backend para AnalyticsService
// ----------------------------------------------------------------------------
// Envia los eventos del AnalyticsService a PostHog (SaaS). El AnalyticsService
// ya enriquece con env / user_id / tenant_id / correlation_id antes de
// llamar a `track`, asi que aqui solo reenviamos.
//
// **Inicializacion**: hay que llamar a `PosthogConfig` ANTES de runApp() en
// main.dart cuando hay `EnvConfig.posthogApiKey` no vacia. Si no se
// inicializa, no_op silencioso (este backend no se selecciona en el
// provider de analytics).
//
// **Privacidad**: por defecto NO captura screenshots ni session replays
// (decision UX + GDPR). Solo eventos discretos via API.
//
// **Region**: usamos `https://eu.i.posthog.com` por defecto (datos en
// Europa, mejor para usuarios de testexamen.es y GDPR). Override con
// `--dart-define=POSTHOG_HOST=...`.
// ============================================================================

import 'package:posthog_flutter/posthog_flutter.dart';

import '../utils/app_logger.dart';
import 'analytics_event.dart';
import 'analytics_service.dart';

class PostHogAnalyticsBackend implements AnalyticsBackend {
  PostHogAnalyticsBackend();

  static final Posthog _ph = Posthog();

  @override
  Future<void> track(AnalyticsEvent event) async {
    try {
      await _ph.capture(
        eventName: event.name,
        properties: _stringifyProps(event.properties),
      );
    } catch (e) {
      // Nunca rompemos el flujo del caller. El AnalyticsService ya hace el
      // catch externo, pero protegemos doble por si acaso.
      AppLogger.w('posthog.track($event.name) failed: $e');
    }
  }

  @override
  Future<void> identify(
    String userId, {
    Map<String, Object?> traits = const {},
  }) async {
    try {
      await _ph.identify(
        userId: userId,
        userProperties: _stringifyProps(traits),
      );
    } catch (e) {
      AppLogger.w('posthog.identify failed: $e');
    }
  }

  @override
  Future<void> reset() async {
    try {
      await _ph.reset();
    } catch (e) {
      AppLogger.w('posthog.reset failed: $e');
    }
  }

  /// PostHog acepta `Map<String, Object>` (no nullable). Filtramos los nulls.
  /// Tambien tira si meten objetos no-serializables, asi que casteamos a
  /// String los que no sean primitivos JSON.
  Map<String, Object> _stringifyProps(Map<String, Object?> raw) {
    final out = <String, Object>{};
    for (final entry in raw.entries) {
      final v = entry.value;
      if (v == null) continue;
      if (v is String || v is num || v is bool) {
        out[entry.key] = v;
      } else {
        out[entry.key] = v.toString();
      }
    }
    return out;
  }
}
