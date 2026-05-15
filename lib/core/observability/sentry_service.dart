import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/env_config.dart';
import '../utils/log_context.dart';

/// Fachada sobre Sentry. **Diseño**:
///
/// - Si `SENTRY_DSN` no se pasa por `--dart-define`, el servicio queda
///   inactivo: las llamadas a [capture] son no-op, perfecto para dev/CI sin
///   cuenta de Sentry.
/// - Si está activo, [init] inicializa el SDK con el DSN + `environment` +
///   `release` (toma `APP_VERSION` si lo pasas por --dart-define).
/// - Las llamadas a [capture] y [captureMessage] adjuntan automáticamente:
///   - `correlation_id` del [LogContext] actual.
///   - Cualquier `tag` que esté en el LogContext.
///
/// Uso:
///
/// ```dart
/// // En main.dart, después de cargar EnvConfig:
/// await SentryService.init(runApp: () async => runApp(MyApp()));
///
/// // En cualquier sitio:
/// AppLogger.e('boom', error: e, stackTrace: st); // ya llama a Sentry.
/// ```
class SentryService {
  SentryService._();

  static bool _enabled = false;

  /// `true` si Sentry está inicializado y recibirá eventos.
  static bool get isEnabled => _enabled;

  /// DSN recibido por `--dart-define=SENTRY_DSN=...`. Vacío si no se pasó.
  static const String _dsn = String.fromEnvironment('SENTRY_DSN');

  /// Versión de la release. Por convención `<app>@<semver>+<build>` —
  /// recibida por `--dart-define=APP_VERSION=...`. Vacío si no se pasó.
  static const String _release = String.fromEnvironment('APP_VERSION');

  /// Inicializa Sentry **solo si hay DSN configurado**. Si no, ejecuta
  /// directamente [runApp] (no-op). En ambos casos llama a [runApp] dentro
  /// de la zona apropiada — no llames a `runApp` tú aparte.
  static Future<void> init({
    required FutureOr<void> Function() runApp,
  }) async {
    if (_dsn.isEmpty) {
      _enabled = false;
      await runApp();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = _dsn;
        options.environment = _envName();
        if (_release.isNotEmpty) options.release = _release;
        // En dev capturamos absolutamente todo para que el dev pueda probar
        // el setup. En prod 0.2 → 20% sampling para errores no fatales.
        options.tracesSampleRate = kReleaseMode ? 0.2 : 1.0;
        // No subir PII salvo que lo pidamos explícitamente con `User`.
        options.sendDefaultPii = false;
        // Cortar event noise: ignorar errores conocidos que llegan por
        // navegadores con extensiones (ResizeObserver loop limit exceeded
        // típico de Chrome).
        options.beforeSend = (event, hint) {
          final msg = event.message?.formatted ?? '';
          if (msg.contains('ResizeObserver loop')) return null;
          return event;
        };
      },
      appRunner: () async => runApp(),
    );
    _enabled = true;
  }

  /// Captura una excepción adjuntando correlation_id + tags del LogContext.
  /// Safe no-op si Sentry no está inicializado.
  static Future<void> capture(
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?> tags = const {},
    String? message,
  }) async {
    if (!_enabled) return;
    final ctx = LogContext.current;
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (ctx != null) {
          scope.setTag('correlation_id', ctx.correlationId);
          for (final entry in ctx.tags.entries) {
            scope.setTag(entry.key, entry.value?.toString() ?? '');
          }
        }
        for (final entry in tags.entries) {
          scope.setTag(entry.key, entry.value?.toString() ?? '');
        }
        if (message != null) {
          scope.setContexts('message', {'value': message});
        }
      },
    );
  }

  /// Captura un mensaje (no es una excepción). Útil para warnings de negocio
  /// importantes.
  static Future<void> captureMessage(
    String message, {
    SentryLevel level = SentryLevel.warning,
    Map<String, Object?> tags = const {},
  }) async {
    if (!_enabled) return;
    final ctx = LogContext.current;
    await Sentry.captureMessage(
      message,
      level: level,
      withScope: (scope) {
        if (ctx != null) {
          scope.setTag('correlation_id', ctx.correlationId);
          for (final entry in ctx.tags.entries) {
            scope.setTag(entry.key, entry.value?.toString() ?? '');
          }
        }
        for (final entry in tags.entries) {
          scope.setTag(entry.key, entry.value?.toString() ?? '');
        }
      },
    );
  }

  /// Asocia un usuario a los eventos posteriores en esta sesión. Pásale
  /// `null` para des-asociar (logout).
  static Future<void> setUser({
    String? id,
    String? email,
    String? username,
  }) async {
    if (!_enabled) return;
    if (id == null && email == null && username == null) {
      await Sentry.configureScope((scope) => scope.setUser(null));
      return;
    }
    await Sentry.configureScope(
      (scope) => scope.setUser(
        SentryUser(id: id, email: email, username: username),
      ),
    );
  }

  static String _envName() => switch (EnvConfig.environment) {
        Environment.development => 'dev',
        Environment.staging => 'staging',
        Environment.production => 'prod',
      };
}
