import 'package:flutter_dotenv/flutter_dotenv.dart';

enum Environment { development, staging, production }

class EnvConfig {
  EnvConfig._();

  static Environment _environment = Environment.development;

  static Environment get environment => _environment;
  static bool get isProduction => _environment == Environment.production;
  static bool get isDevelopment => _environment == Environment.development;

  static String get appName => dotenv.get('APP_NAME', fallback: 'myapp');

  // Supabase
  static String get supabaseUrl => dotenv.get('SUPABASE_URL', fallback: '');
  static String get supabaseAnonKey =>
      dotenv.get('SUPABASE_ANON_KEY', fallback: '');

  // Auth — coincidir con Supabase Dashboard → Auth → Email OTP Length.
  // Clamp [4, 10] para no aceptar valores absurdos por error de tipeo.
  static int get otpCodeLength {
    final raw = int.tryParse(dotenv.get('OTP_CODE_LENGTH', fallback: '6')) ?? 6;
    return raw.clamp(4, 10);
  }

  // Feature flags
  static bool get enableLogging =>
      dotenv.get('ENABLE_LOGGING', fallback: 'true').toLowerCase() == 'true';
  static bool get enableAnalytics =>
      dotenv.get('ENABLE_ANALYTICS', fallback: 'false').toLowerCase() == 'true';

  static Future<void> load({Environment env = Environment.development}) async {
    _environment = env;
    await dotenv.load();
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env file',
      );
    }
  }
}
