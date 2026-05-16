import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Entorno de ejecución de la app. Lo selecciona `main.dart` a partir del
/// `--dart-define=ENV=<dev|staging|prod>` y se usa para:
///   - banner visible (dev/staging) que recuerda en qué entorno estás
///   - logging level
///   - flags de debug en SDKs (`debug: !isProduction`)
///   - features que se ocultan en producción (admin shortcuts, etc.)
enum Environment { development, staging, production }

/// Configuración inmutable de la app cargada al inicio en `main.dart`.
///
/// **Orden de prioridad** para leer cada variable:
///   1. `--dart-define=KEY=value` (compile-time, lo que usan CI/CD)
///   2. Archivo `.env` cargado vía `flutter_dotenv` (uso local)
///   3. Fallback documentado en cada getter — error claro si la variable
///      es obligatoria y nadie la proporcionó.
///
/// **Por qué este orden**: en CI/staging/prod el build se hace con
/// `--dart-define-from-file=ci/<env>.json` (o `--dart-define` sueltos)
/// para que NO existan archivos `.env` con credenciales en el filesystem
/// del runner. En local, el `.env` da comodidad. Si en local también
/// pasas un `--dart-define`, gana — útil para probar puntualmente con
/// otras credenciales sin tocar `.env`.
class EnvConfig {
  EnvConfig._();

  static Environment _environment = Environment.development;

  static Environment get environment => _environment;
  static bool get isProduction => _environment == Environment.production;
  static bool get isStaging => _environment == Environment.staging;
  static bool get isDevelopment => _environment == Environment.development;

  // ─────────────────────── App metadata ───────────────────────
  static String get appName =>
      _read('APP_NAME', dartDefine: _appNameDef, fallback: 'myapp');

  /// Inyectado por CI con `--dart-define=APP_VERSION=v1.2.3` (típicamente
  /// el tag de git). Lo lee también Sentry como `release`.
  static String get appVersion =>
      _read('APP_VERSION', dartDefine: _appVersionDef, fallback: '');

  // ─────────────────────── Supabase ───────────────────────
  static String get supabaseUrl =>
      _read('SUPABASE_URL', dartDefine: _supabaseUrlDef);
  static String get supabaseAnonKey =>
      _read('SUPABASE_ANON_KEY', dartDefine: _supabaseAnonKeyDef);

  // ─────────────────────── Observability ───────────────────────
  /// Sentry DSN. Si está vacío, `SentryService` se inicializa como no-op
  /// y los errores siguen apareciendo en consola via `AppLogger` pero no
  /// se envían a Sentry. Útil para devs locales que no quieren
  /// contaminar el proyecto Sentry de la organización.
  static String get sentryDsn =>
      _read('SENTRY_DSN', dartDefine: _sentryDsnDef, fallback: '');

  // ─────────────────────── Auth ───────────────────────
  /// Tamaño del código OTP enviado por Supabase. Debe coincidir con
  /// Supabase Dashboard → Authentication → Email OTP Length.
  /// Clamp [4, 10] por seguridad ante typo del operator.
  static int get otpCodeLength {
    final raw = _read(
      'OTP_CODE_LENGTH',
      dartDefine: _otpLengthDef,
      fallback: '6',
    );
    final n = int.tryParse(raw) ?? 6;
    return n.clamp(4, 10);
  }

  // ─────────────────────── Feature flags ───────────────────────
  static bool get enableLogging => _readBool(
        'ENABLE_LOGGING',
        dartDefine: _enableLoggingDef,
        fallback: true,
      );
  static bool get enableAnalytics => _readBool(
        'ENABLE_ANALYTICS',
        dartDefine: _enableAnalyticsDef,
        fallback: false,
      );

  /// Si `true`, fuerza el modo JSON estructurado del logger incluso en dev.
  /// Útil para probar formato de logs en local sin desplegar.
  static bool get forceStructuredLogs => _readBool(
        'STRUCTURED_LOGS',
        dartDefine: _structuredLogsDef,
        fallback: false,
      );

  /// Carga el entorno. Si no se pasa `env`, se queda como
  /// `development`. Intenta cargar `.env`; si no existe, no error — el
  /// resto de getters usa `--dart-define` o fallback.
  ///
  /// Lanza solo si tras cargar TODO, faltan variables OBLIGATORIAS
  /// (`SUPABASE_URL` y `SUPABASE_ANON_KEY`).
  static Future<void> load({Environment env = Environment.development}) async {
    _environment = env;
    try {
      await dotenv.load();
    } catch (_) {
      // Sin .env tampoco se rompe — el build de CI proporciona todo via
      // --dart-define.
    }
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Missing SUPABASE_URL or SUPABASE_ANON_KEY. '
        'Provide via .env (local) or --dart-define (CI/build).',
      );
    }
  }

  // ─────────────────────── Helpers ───────────────────────

  /// Lee primero del compile-time const (pasado por `--dart-define`); si
  /// está vacío, cae al `.env`; si no, al fallback.
  static String _read(
    String key, {
    required String dartDefine,
    String? fallback,
  }) {
    if (dartDefine.isNotEmpty) return dartDefine;
    return dotenv.get(key, fallback: fallback ?? '');
  }

  static bool _readBool(
    String key, {
    required String dartDefine,
    required bool fallback,
  }) {
    final raw = _read(
      key,
      dartDefine: dartDefine,
      fallback: fallback.toString(),
    );
    return raw.toLowerCase() == 'true';
  }

  // ─────────────────────── Compile-time defines ───────────────────────
  //
  // `String.fromEnvironment` es const-only: cada variable necesita su
  // propia constante. Los enumeramos aquí para que `_read` las pueda
  // resolver dinámicamente sin reflection.
  //
  // El nombre del símbolo Dart no tiene que coincidir con el del KEY,
  // solo importa el `String.fromEnvironment('KEY')`.

  static const String _appNameDef =
      String.fromEnvironment('APP_NAME');
  static const String _appVersionDef =
      String.fromEnvironment('APP_VERSION');
  static const String _supabaseUrlDef =
      String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKeyDef =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _sentryDsnDef =
      String.fromEnvironment('SENTRY_DSN');
  static const String _otpLengthDef =
      String.fromEnvironment('OTP_CODE_LENGTH');
  static const String _enableLoggingDef =
      String.fromEnvironment('ENABLE_LOGGING');
  static const String _enableAnalyticsDef =
      String.fromEnvironment('ENABLE_ANALYTICS');
  static const String _structuredLogsDef =
      String.fromEnvironment('STRUCTURED_LOGS');
}
