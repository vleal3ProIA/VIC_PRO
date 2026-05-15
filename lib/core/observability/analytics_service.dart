import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/tenants/application/tenant_providers.dart';

import '../config/env_config.dart';
import '../providers/supabase_providers.dart';
import '../utils/app_logger.dart';
import '../utils/log_context.dart';
import 'analytics_event.dart';

/// Backend pluggable para `AnalyticsService`. Cada implementación decide
/// adónde envía los eventos (consola, PostHog, GA4, Amplitude, etc.).
abstract class AnalyticsBackend {
  Future<void> track(AnalyticsEvent event);
  Future<void> identify(String userId, {Map<String, Object?> traits = const {}});
  Future<void> reset();
}

/// Backend por defecto: no envía a ningún SaaS, solo loguea con AppLogger
/// a nivel `info`. Útil en dev (ves los eventos en consola JSON) y en
/// staging/CI sin necesidad de cuenta externa.
class LoggingAnalyticsBackend implements AnalyticsBackend {
  const LoggingAnalyticsBackend();

  @override
  Future<void> track(AnalyticsEvent event) async {
    AppLogger.i('analytics.${event.name}', tags: event.properties);
  }

  @override
  Future<void> identify(
    String userId, {
    Map<String, Object?> traits = const {},
  }) async {
    AppLogger.i('analytics.identify', tags: {'user_id': userId, ...traits});
  }

  @override
  Future<void> reset() async {
    AppLogger.i('analytics.reset');
  }
}

/// No-op para tests / cuando analytics está desactivado: ni siquiera loguea.
class NoopAnalyticsBackend implements AnalyticsBackend {
  const NoopAnalyticsBackend();

  @override
  Future<void> track(AnalyticsEvent event) async {}

  @override
  Future<void> identify(
    String userId, {
    Map<String, Object?> traits = const {},
  }) async {}

  @override
  Future<void> reset() async {}
}

/// Servicio de analytics que enriquece cada evento con metadata canónica
/// y delega el envío en un [AnalyticsBackend].
///
/// Metadata adjuntada automáticamente:
/// - `user_id`     ← sesión actual de Supabase (si la hay).
/// - `correlation_id` ← del [LogContext] activo (si lo hay).
/// - `env`         ← dev / staging / prod.
/// - cualquier `tag` del [LogContext].
class AnalyticsService {
  AnalyticsService({
    required this.backend,
    this.getUserId,
    this.getTenantId,
  });

  final AnalyticsBackend backend;

  /// Callback opcional para resolver el `user_id` actual sin acoplar el
  /// servicio a Riverpod. El provider lo conecta a `currentUserProvider`;
  /// los tests pueden inyectar el suyo o dejarlo `null`.
  final String? Function()? getUserId;

  /// Callback opcional para resolver el `tenant_id` actual. Enriquece cada
  /// evento con la dimensión "tenant" — fundamental para segmentar funnels
  /// y rendimiento por workspace.
  final String? Function()? getTenantId;

  String? _lastIdentifiedUser;

  /// Registra un evento. **No bloquea**: errores en el backend solo loguean
  /// un warning.
  Future<void> track(
    String name, {
    Map<String, Object?> properties = const {},
  }) async {
    final enriched = _enrich(properties);
    try {
      await backend.track(AnalyticsEvent(name, enriched));
    } catch (e, st) {
      AppLogger.w('analytics.track($name) failed: $e');
      // No re-lanzamos: analytics nunca debe romper el flujo.
      // ignore: avoid_catching_errors
      assert(() {
        // En dev queremos verlo bien, no solo el `w`.
        AppLogger.e('analytics backend error', error: e, stackTrace: st);
        return true;
      }(),
        'analytics backend exception (only visible in dev)',);
    }
  }

  /// Versión sin `await` para call-sites donde no quieres hacer fire-and-forget
  /// manual. **Sigue siendo no-bloqueante**: descarta el future internamente.
  void trackSync(
    String name, {
    Map<String, Object?> properties = const {},
  }) {
    // ignore: discarded_futures
    track(name, properties: properties);
  }

  /// Asocia un usuario al stream de eventos. Idempotente: si ya se identificó
  /// ese mismo `userId`, no re-envía.
  Future<void> identify(
    String userId, {
    Map<String, Object?> traits = const {},
  }) async {
    if (_lastIdentifiedUser == userId) return;
    _lastIdentifiedUser = userId;
    try {
      await backend.identify(userId, traits: traits);
    } catch (e) {
      AppLogger.w('analytics.identify failed: $e');
    }
  }

  /// Desidentifica (logout). Resetea el caché.
  Future<void> reset() async {
    _lastIdentifiedUser = null;
    try {
      await backend.reset();
    } catch (e) {
      AppLogger.w('analytics.reset failed: $e');
    }
  }

  // ─── Internals ───────────────────────────────────────────────────────────

  Map<String, Object?> _enrich(Map<String, Object?> base) {
    final ctx = LogContext.current;
    final userId = getUserId?.call();
    final tenantId = getTenantId?.call();
    return <String, Object?>{
      ...base,
      'env': _envName(),
      if (userId != null) 'user_id': userId,
      if (tenantId != null) 'tenant_id': tenantId,
      if (ctx != null) 'correlation_id': ctx.correlationId,
      if (ctx != null) ...ctx.tags,
    };
  }

  static String _envName() => switch (EnvConfig.environment) {
        Environment.development => 'dev',
        Environment.staging => 'staging',
        Environment.production => 'prod',
      };
}

/// Provider del [AnalyticsService].
///
/// Por defecto usa [LoggingAnalyticsBackend] en cualquier entorno donde
/// `ENABLE_ANALYTICS` esté activo, y [NoopAnalyticsBackend] si no. Los tests
/// lo sobrescriben con [NoopAnalyticsBackend] explícito.
///
/// Cuando integremos un backend real (PostHog, GA4…), basta con cambiar la
/// implementación aquí — el resto de la app sigue llamando a `track(...)`.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final backend = EnvConfig.enableAnalytics
      ? const LoggingAnalyticsBackend()
      : const NoopAnalyticsBackend();
  return AnalyticsService(
    backend: backend,
    getUserId: () => ref.read(currentUserProvider)?.id,
    // `currentTenantIdProvider` se importa de features/tenants. Romper la
    // dependencia "core no depende de features" sería sobrediseño aquí:
    // el feature de observabilidad SÍ necesita saber el tenant actual
    // para que cada evento lo lleve.
    getTenantId: () => ref.read(currentTenantIdProvider),
  );
});

/// Side-effect-only: mantiene `identify` / `reset` sincronizado con la
/// sesión actual.
final analyticsUserSyncProvider = Provider<void>((ref) {
  ref.listen(currentUserProvider, (prev, next) {
    final svc = ref.read(analyticsServiceProvider);
    if (next == null) {
      // ignore: discarded_futures
      svc.reset();
    } else {
      // ignore: discarded_futures
      svc.identify(
        next.id,
        traits: {
          if (next.email != null) 'email': next.email,
        },
      );
    }
  },
    fireImmediately: true,
  );
});
