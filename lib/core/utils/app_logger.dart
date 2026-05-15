import 'dart:convert';
import 'dart:developer' as developer;

import 'package:logger/logger.dart';

import '../config/env_config.dart';
import '../observability/sentry_service.dart';
import 'log_context.dart';

/// Wrapper de logging. **Dos modos**:
///
/// - **Pretty** (desarrollo, `EnvConfig.isDevelopment`): salida coloreada
///   tipo `logger` package — legible mientras desarrollas.
/// - **JSON estructurado** (staging / production): una línea JSON por log,
///   apta para parsing por colectores (Datadog, Loki, BigQuery, etc.).
///
/// La API estática (`d`/`i`/`w`/`e`) es idéntica en ambos modos para no
/// romper los call-sites existentes.
///
/// Cada log JSON lleva:
///
/// | Campo            | Origen                                  |
/// |------------------|-----------------------------------------|
/// | `ts`             | UTC ISO-8601                            |
/// | `level`          | debug \| info \| warn \| error          |
/// | `msg`            | el `message` que pasaste                |
/// | `env`            | dev \| staging \| prod                  |
/// | `app`            | `EnvConfig.appName`                     |
/// | `correlation_id` | de `LogContext.current.correlationId`   |
/// | `tags`           | de `LogContext.current.tags`            |
/// | `error`          | `e.toString()` (solo en `.e()`)         |
/// | `stack`          | `stackTrace.toString()` (solo en `.e()`)|
class AppLogger {
  AppLogger._();

  // Para los tests: permite sustituir el sink y observar lo que se imprime.
  // En runtime real, [_emit] llama a `developer.log` (devtools) y por defecto
  // a `print` a stdout (que en Flutter Web → console.log).
  /// Sink usado para emitir logs JSON. `null` = sink real (developer.log).
  /// Los tests lo sobrescriben para capturar líneas en memoria.
  static void Function(String line, {Level level})? testSink;

  static final Level _minLevel =
      EnvConfig.enableLogging ? Level.debug : Level.warning;

  static final Logger _prettyLogger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 100,
      colors: true,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: _minLevel,
  );

  /// `true` si los logs salen como JSON estructurado. Por defecto en
  /// staging/production; configurable vía `STRUCTURED_LOGS=true` en `.env`
  /// si quieres forzarlo en dev para probar el formato.
  static bool get _structured {
    if (EnvConfig.forceStructuredLogs) return true;
    return !EnvConfig.isDevelopment;
  }

  static void d(Object? message, {Map<String, Object?>? tags}) =>
      _log(Level.debug, message, tags: tags);

  static void i(Object? message, {Map<String, Object?>? tags}) =>
      _log(Level.info, message, tags: tags);

  static void w(Object? message, {Map<String, Object?>? tags}) =>
      _log(Level.warning, message, tags: tags);

  static void e(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? tags,
  }) {
    _log(Level.error, message, error: error, stackTrace: stackTrace, tags: tags);
    // Fire-and-forget: enviamos a Sentry si está activo. No bloqueamos
    // el flujo del logger por una llamada de red.
    if (error != null) {
      // ignore: discarded_futures
      SentryService.capture(
        error,
        stackTrace: stackTrace,
        tags: tags ?? const {},
        message: message?.toString(),
      );
    } else if (message != null) {
      // ignore: discarded_futures
      SentryService.captureMessage(
        message.toString(),
        tags: tags ?? const {},
      );
    }
  }

  // ─── Internals ───────────────────────────────────────────────────────────

  static void _log(
    Level level,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? tags,
  }) {
    // En cualquier modo, si el nivel está por debajo del configurado, salimos.
    if (level.index < _minLevel.index) return;

    if (_structured) {
      final line = _jsonLine(
        level: level,
        message: message,
        error: error,
        stackTrace: stackTrace,
        tags: tags,
      );
      _emit(line, level: level);
    } else {
      // Modo dev: usamos el logger bonito. Si hay correlation_id, lo
      // prefijamos para que sea visible.
      final ctx = LogContext.current;
      final prefix = ctx == null ? '' : '[${ctx.correlationId}] ';
      final extra = (tags == null || tags.isEmpty) ? '' : ' $tags';
      final composed = '$prefix$message$extra';
      switch (level) {
        case Level.debug:
          _prettyLogger.d(composed);
        case Level.warning:
          _prettyLogger.w(composed);
        case Level.error:
          _prettyLogger.e(composed, error: error, stackTrace: stackTrace);
        // ignore: no_default_cases
        default:
          _prettyLogger.i(composed);
      }
    }
  }

  static String _jsonLine({
    required Level level,
    required Object? message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? tags,
  }) {
    final ctx = LogContext.current;
    final mergedTags = <String, Object?>{
      ...?ctx?.tags,
      ...?tags,
    };
    final json = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': _levelToString(level),
      'msg': message?.toString() ?? '',
      'env': _envName(),
      'app': EnvConfig.appName,
      if (ctx != null) 'correlation_id': ctx.correlationId,
      if (mergedTags.isNotEmpty) 'tags': mergedTags,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
    };
    return jsonEncode(json);
  }

  static String _levelToString(Level level) => switch (level) {
        Level.debug => 'debug',
        Level.info => 'info',
        Level.warning => 'warn',
        Level.error => 'error',
        _ => 'info',
      };

  static String _envName() => switch (EnvConfig.environment) {
        Environment.development => 'dev',
        Environment.staging => 'staging',
        Environment.production => 'prod',
      };

  static void _emit(String line, {required Level level}) {
    final sink = testSink;
    if (sink != null) {
      sink(line, level: level);
      return;
    }
    // `developer.log` en Flutter va a DevTools; `print` va a stdout/console.log
    // (en web). Usamos `print` para que tooling externo capture la línea JSON.
    // ignore: avoid_print
    developer.log(line, name: 'app');
  }
}
