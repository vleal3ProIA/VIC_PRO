import 'dart:async';
import 'dart:math';

/// Contexto de logging propagado por `Zone`: cuando una operación se ejecuta
/// dentro de [LogContext.run], cualquier `AppLogger.x(...)` que se dispare
/// (incluso varios niveles de `await` más abajo, en otro provider, otro
/// callback) hereda el `correlationId` y `tags` automáticamente.
///
/// Esto es la pieza que convierte logs sueltos en una traza:
///
/// ```dart
/// await LogContext.run(
///   correlationId: LogContext.newCorrelationId(),
///   tags: {'flow': 'signup', 'email': 'a@b.com'},
///   () async {
///     AppLogger.i('signup started');         // ← lleva correlation_id
///     await repo.signUp(...);                // ← logs internos también
///     AppLogger.i('signup ok');              // ← misma correlation_id
///   },
/// );
/// ```
class LogContext {
  LogContext._({required this.correlationId, this.tags = const {}});

  /// Identificador único de la operación. Va en cada línea JSON como
  /// `correlation_id`.
  final String correlationId;

  /// Pares clave/valor que se serializan en cada log como `tags`. Útil para
  /// adjuntar `user_id`, `tenant_id`, `flow`, etc. al contexto entero.
  final Map<String, Object?> tags;

  // ─── Zone key ─────────────────────────────────────────────────────────────

  static const _key = #app_logger_context;

  /// El [LogContext] actualmente activo, si lo hay. Lo lee `AppLogger`
  /// internamente. Devuelve `null` fuera de una llamada a [run].
  static LogContext? get current {
    final value = Zone.current[_key];
    return value is LogContext ? value : null;
  }

  /// Genera un identificador corto (12 chars base36) suficiente para que sea
  /// único dentro de la sesión de un usuario sin necesitar la dependencia
  /// `uuid`. Si quieres trazas multi-servicio reemplaza por v7 con tiempo.
  static String newCorrelationId() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Ejecuta [body] con un [LogContext] activo. Si ya hay uno, las [tags]
  /// nuevas se **fusionan** con las del padre (las del hijo ganan). El
  /// [correlationId] siempre se sobrescribe con el del nuevo contexto.
  static Future<T> run<T>(
    Future<T> Function() body, {
    String? correlationId,
    Map<String, Object?> tags = const {},
  }) {
    final parent = current;
    final merged = {...?parent?.tags, ...tags};
    final ctx = LogContext._(
      correlationId: correlationId ?? parent?.correlationId ?? newCorrelationId(),
      tags: merged,
    );
    return runZoned<Future<T>>(body, zoneValues: {_key: ctx});
  }

  /// Versión síncrona de [run].
  static T runSync<T>(
    T Function() body, {
    String? correlationId,
    Map<String, Object?> tags = const {},
  }) {
    final parent = current;
    final merged = {...?parent?.tags, ...tags};
    final ctx = LogContext._(
      correlationId: correlationId ?? parent?.correlationId ?? newCorrelationId(),
      tags: merged,
    );
    return runZoned<T>(body, zoneValues: {_key: ctx});
  }
}
